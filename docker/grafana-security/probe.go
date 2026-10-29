package main

import (
	"bytes"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"time"
)

var client = &http.Client{Timeout: 12 * time.Second}

func request(method, path string, body any) (int, []byte) {
	var content io.Reader
	if body != nil {
		b, err := json.Marshal(body)
		if err != nil {
			panic(err)
		}
		content = bytes.NewReader(b)
	}
	q, err := http.NewRequest(method, "http://127.0.0.1:8090"+path, content)
	if err != nil {
		panic(err)
	}
	q.Header.Set("Content-Type", "application/json")
	r, err := client.Do(q)
	if err != nil {
		panic(err)
	}
	defer r.Body.Close()
	b, err := io.ReadAll(r.Body)
	if err != nil {
		panic(err)
	}
	return r.StatusCode, b
}

func ok(method, path string, body any) []byte {
	s, b := request(method, path, body)
	if s != 200 {
		panic(fmt.Sprintf("%s %s: %d %s", method, path, s, b))
	}
	return b
}

func mock() {
	var ca string
	h := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		switch r.URL.Path {
		case "/fixture/ca":
			w.Header().Set("Content-Type", "text/plain")
			fmt.Fprint(w, ca)
		case "/api/echo":
			w.Header().Set("Content-Type", "text/plain")
			fmt.Fprint(w, "echo")
		case "/api/v1/status/buildinfo":
			fmt.Fprint(w, `{"status":"success","data":{"version":"3.14.0"}}`)
		case "/api/status/buildinfo":
			fmt.Fprint(w, `{"version":"2.10.10"}`)
		case "/api/v1/query", "/api/v1/query_range", "/loki/api/v1/query":
			fmt.Fprintf(w, `{"status":"success","data":{"resultType":"vector","result":[{"metric":{"__name__":"up"},"value":[%d,"2"]}]}}`, time.Now().Unix())
		case "/loki/api/v1/labels":
			fmt.Fprint(w, `{"status":"success","data":["fixture"]}`)
		case "/api/search":
			fmt.Fprint(w, `{"traces":[],"metrics":{"inspectedTraces":0,"inspectedBytes":"0","totalBlocks":0}}`)
		default:
			fmt.Fprint(w, `{"status":"success","data":[]}`)
		}
	})
	listener, err := net.Listen("tcp", "127.0.0.1:19443")
	if err != nil {
		panic(err)
	}
	s := httptest.NewUnstartedServer(h)
	s.Listener.Close()
	s.Listener = listener
	s.Config.ErrorLog = log.New(io.Discard, "", 0)
	s.StartTLS()
	defer s.Close()
	ca = string(pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: s.Certificate().Raw}))
	if err := http.ListenAndServe("127.0.0.1:19090", h); err != nil {
		panic(err)
	}
}

func seed() {
	ok("POST", "/api/dashboards/db", map[string]any{"dashboard": map[string]any{"id": nil, "uid": "security-go-fixture", "title": "Security compiler fixture", "schemaVersion": 39, "version": 0, "panels": []any{}}, "overwrite": false})
	r, err := client.Get("http://127.0.0.1:19090/fixture/ca")
	if err != nil {
		panic(err)
	}
	ca, err := io.ReadAll(r.Body)
	r.Body.Close()
	if err != nil {
		panic(err)
	}
	for _, kind := range []string{"prometheus", "loki", "tempo"} {
		ok("POST", "/api/datasources", map[string]any{"uid": "security-" + kind, "name": "Security " + kind, "type": kind, "url": "http://127.0.0.1:19090", "access": "proxy", "jsonData": map[string]any{}})
	}
	for _, trusted := range []bool{false, true} {
		uid := "security-tls-untrusted"
		data := map[string]any{"tlsSkipVerify": false}
		secure := map[string]any{}
		if trusted {
			uid = "security-tls-trusted"
			data["tlsAuthWithCACert"] = true
			secure["tlsCACert"] = string(ca)
		}
		ok("POST", "/api/datasources", map[string]any{"uid": uid, "name": uid, "type": "prometheus", "url": "https://127.0.0.1:19443", "access": "proxy", "jsonData": data, "secureJsonData": secure})
	}
	fmt.Println(`{"seeded":true,"production_data_used":false}`)
}

func verify(expectedFile string) {
	checks := []string{}
	var health map[string]any
	if err := json.Unmarshal(ok("GET", "/api/health", nil), &health); err != nil {
		panic(err)
	}
	if health["version"] != "13.2.4" || health["database"] != "ok" {
		panic(health)
	}
	checks = append(checks, "health/version/database")
	var dashboard struct{ Dashboard struct{ UID, Title string } }
	if err := json.Unmarshal(ok("GET", "/api/dashboards/uid/security-go-fixture", nil), &dashboard); err != nil {
		panic(err)
	}
	if dashboard.Dashboard.UID != "security-go-fixture" || dashboard.Dashboard.Title != "Security compiler fixture" {
		panic("dashboard changed")
	}
	checks = append(checks, "existing dashboard preserved")
	var expected map[string]string
	raw, err := os.ReadFile(expectedFile)
	if err != nil {
		panic(err)
	}
	if err = json.Unmarshal(raw, &expected); err != nil {
		panic(err)
	}
	var plugins []struct {
		ID, Signature string
		Info          struct{ Version string }
	}
	if err = json.Unmarshal(ok("GET", "/api/plugins", nil), &plugins); err != nil {
		panic(err)
	}
	found := map[string]bool{}
	for _, p := range plugins {
		if version, needed := expected[p.ID]; needed {
			if p.Info.Version != version || p.Signature != "valid" {
				panic(fmt.Sprintf("plugin %s: version=%s signature=%s", p.ID, p.Info.Version, p.Signature))
			}
			found[p.ID] = true
		}
	}
	if len(found) != len(expected) {
		panic(fmt.Sprintf("plugin coverage %d/%d", len(found), len(expected)))
	}
	checks = append(checks, "13 plugin versions and signatures")
	for _, kind := range []string{"prometheus", "loki", "tempo"} {
		var result map[string]any
		if err = json.Unmarshal(ok("GET", "/api/datasources/uid/security-"+kind+"/health", nil), &result); err != nil {
			panic(err)
		}
		if result["status"] != "OK" {
			panic(fmt.Sprintf("%s health: %v", kind, result))
		}
		checks = append(checks, kind+" plugin health")
	}
	for _, test := range []struct{ path, contains string }{
		{"/api/datasources/proxy/uid/security-prometheus/api/v1/query?query=up", `"status":"success"`},
		{"/api/datasources/proxy/uid/security-loki/loki/api/v1/labels", `"fixture"`},
		{"/api/datasources/proxy/uid/security-tempo/api/echo", "echo"},
		{"/api/datasources/proxy/uid/security-tls-trusted/api/v1/query?query=up", `"status":"success"`},
	} {
		if b := ok("GET", test.path, nil); !strings.Contains(string(b), test.contains) {
			panic(string(b))
		}
		checks = append(checks, test.path)
	}
	status, body := request("GET", "/api/datasources/proxy/uid/security-tls-untrusted/api/v1/query?query=up", nil)
	if status != 502 {
		panic(fmt.Sprintf("untrusted TLS not rejected: %d %s", status, body))
	}
	checks = append(checks, "untrusted TLS proxy returned 502; require matching x509 runtime log")
	json.NewEncoder(os.Stdout).Encode(map[string]any{"passed": len(checks), "checks": checks, "production_data_used": false})
}

func main() {
	switch os.Args[1] {
	case "mock":
		mock()
	case "health":
		fmt.Println(string(ok("GET", "/api/health", nil)))
	case "seed":
		seed()
	case "verify":
		verify(os.Args[2])
	default:
		panic("unknown mode")
	}
}
