"""Exercise compiler/plugin candidates using synthetic data in isolated Docker only."""
import datetime,json,os,subprocess,time,uuid,sys,tempfile,shutil
from pathlib import Path
root=Path(__file__).resolve().parent
out=Path(tempfile.mkdtemp(prefix='grafana-security-'))
pins=json.loads((root/'pins.json').read_text())
shutil.copyfile(root/'probe.go',out/'grafana-security-probe.go')
def run(args,timeout=60): return subprocess.run(args,text=True,capture_output=True,timeout=timeout)
def checked(args,timeout=60):
    p=run(args,timeout)
    assert p.returncode==0,(args,p.stdout[-2000:],p.stderr[-2000:])
    return p.stdout.strip()
assert not os.environ.get('DOCKER_HOST')
assert json.loads(checked(['docker','context','inspect']))[0]['Endpoints']['docker']['Host']=='unix:///var/run/docker.sock'
probe=out/'grafana-security-probe.go';binary=out/'grafana-security-probe'
checked(['gofmt','-w',str(probe)])
env=dict(os.environ,CGO_ENABLED='0',GOMAXPROCS='2',GOFLAGS='-p=2')
p=subprocess.run(['go','build','-o',str(binary),str(probe)],env=env,text=True,capture_output=True,timeout=120)
assert p.returncode==0,p.stderr
base=pins['baseline_plugins']
updated=dict(base)
for p in pins['plugins']: updated[p['plugin']]=p['candidate']
for name,data in [('original',base),('updated',updated)]: (out/f'expected-plugins-{name}.json').write_text(json.dumps(data))
core,candidate=sys.argv[1:]
stages=[('original',pins['base'],'original'),('core',core,'original'),('plugins',candidate,'updated')]
original_config=json.loads(checked(['docker','image','inspect',pins['base']]))[0]['Config']
metadata={}
for stage,image,_ in stages:
    actual=json.loads(checked(['docker','image','inspect',image]))[0]['Config']
    for key in ('User','Entrypoint','Cmd','Env','WorkingDir','ExposedPorts'):
        assert actual.get(key)==original_config.get(key),(stage,key)
    cid=checked(['docker','create',image])
    try: checked(['docker','cp',cid+':/usr/share/grafana/bin/grafana',str(out/('binary-'+stage))])
    finally: checked(['docker','rm',cid])
    metadata[stage]=checked(['go','version','-m',str(out/('binary-'+stage))])
    (out/('buildinfo-'+stage+'.txt')).write_text(metadata[stage])
deps=lambda value: sorted(line.strip() for line in value.splitlines() if line.startswith(('\tdep\t','\t=>\t')))
assert ': go1.26.9' in metadata['original']
for stage in ('core','plugins'):
    assert ': go1.26.10' in metadata[stage]
    assert deps(metadata[stage])==deps(metadata['original'])
volume='codex-grafana-ca-test-'+uuid.uuid4().hex[:12]
checked(['docker','volume','create','--label','codex.security-sweep=grafana-go12610',volume])
records=[];state={'utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'volume':volume,'production_data_used':False,'checks':records}
statefile=out/'grafana-security-validation.json'
statefile.write_text(json.dumps(state,indent=2))
try:
    for stage,image,expected in stages:
        cmd=['docker','run','-d','--label','codex.security-sweep=grafana-go12610','--network','none','--read-only','--cap-drop','ALL','--security-opt','no-new-privileges','--cpus','2','--memory','1536m','--tmpfs','/tmp','-v',volume+':/var/lib/grafana','-v',str(binary)+':/probe:ro','-v',str(out/f'expected-plugins-{expected}.json')+':/expected.json:ro']
        for setting in ['GF_SERVER_HTTP_ADDR=127.0.0.1','GF_SERVER_HTTP_PORT=8090','GF_AUTH_ANONYMOUS_ENABLED=true','GF_AUTH_ANONYMOUS_ORG_ROLE=Admin','GF_AUTH_BASIC_ENABLED=false','GF_ANALYTICS_REPORTING_ENABLED=false','GF_ANALYTICS_CHECK_FOR_UPDATES=false','GF_ANALYTICS_CHECK_FOR_PLUGIN_UPDATES=false']:
            cmd+=['-e',setting]
        cid=checked(cmd+[image]);print(json.dumps({'stage':stage,'container':cid,'status':'started'}),flush=True)
        try:
            checked(['docker','exec','-d',cid,'/probe','mock'])
            ready=False
            for attempt in range(40):
                p=run(['docker','exec',cid,'/probe','health'],15)
                if p.returncode==0: ready=True;break
                time.sleep(2)
            assert ready,('readiness failed',stage,p.stdout,p.stderr)
            if stage=='original': checked(['docker','exec',cid,'/probe','seed'])
            p=run(['docker','exec',cid,'/probe','verify','/expected.json'],120)
            (out/f'security-test-{stage}.log').write_text(p.stdout+p.stderr)
            assert p.returncode==0,(stage,p.stdout,p.stderr)
            logs=checked(['docker','logs',cid])
            evidence=[line for line in logs.splitlines() if 'path=/api/datasources/proxy/uid/security-tls-untrusted/' in line and 'x509: certificate signed by unknown authority' in line]
            assert len(evidence)==1,('missing precise TLS rejection evidence',stage)
            record={'stage':stage,'image':image,'result':json.loads(p.stdout),'signature_verification_unchanged':True,'network':'none'}
            record['untrusted_tls_rejection_log']=evidence[0]
            records.append(record);statefile.write_text(json.dumps(state,indent=2));print(json.dumps(record),flush=True)
        finally:
            logs=run(['docker','logs',cid]);(out/f'security-runtime-{stage}.log').write_text(logs.stdout+logs.stderr)
            checked(['docker','stop','-t','10',cid],25);checked(['docker','rm',cid])
    labels=json.loads(checked(['docker','volume','inspect',volume]))[0]['Labels']
    assert labels.get('codex.security-sweep')=='grafana-go12610'
    checked(['docker','volume','rm',volume])
    state['temporary_volume_removed']=True;state['completed_utc']=datetime.datetime.now(datetime.timezone.utc).isoformat()
except Exception as e:
    state['error']=str(e);state['temporary_volume_retained_for_diagnosis']=True
    raise
finally: statefile.write_text(json.dumps(state,indent=2))

print('Evidence: '+str(out),flush=True)
