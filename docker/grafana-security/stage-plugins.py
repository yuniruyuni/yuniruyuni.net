"""Download exact official archives, preserving files covered by Grafana signatures."""
import hashlib
import json
from pathlib import Path, PurePosixPath
import shutil
import stat
import subprocess
import sys
import tempfile
import urllib.request
import zipfile

pins = json.loads(Path(__file__).with_name("pins.json").read_text())
destination = Path(sys.argv[1]).resolve()
destination.mkdir(parents=True, exist_ok=True)
for plugin in pins["plugins"]:
    with tempfile.TemporaryDirectory() as temporary:
        archive = Path(temporary) / "plugin.zip"
        with urllib.request.urlopen(plugin["url"], timeout=90) as response, archive.open("wb") as output:
            shutil.copyfileobj(response, output)
        with archive.open("rb") as stream:
            assert hashlib.file_digest(stream, "sha256").hexdigest() == plugin["catalog_sha256_verified"]
        target = destination / plugin["plugin"]
        assert not target.exists()
        target.mkdir()
        with zipfile.ZipFile(archive) as bundle:
            roots = {PurePosixPath(item.filename).parts[0] for item in bundle.infolist()}
            assert len(roots) == 1
            assert sum(item.file_size for item in bundle.infolist()) < 1_000_000_000
            for item in bundle.infolist():
                path = PurePosixPath(item.filename)
                mode = item.external_attr >> 16
                assert not path.is_absolute() and ".." not in path.parts and not stat.S_ISLNK(mode)
                output = target.joinpath(*path.parts[1:])
                assert output.resolve().is_relative_to(target)
                if item.is_dir():
                    output.mkdir(parents=True, exist_ok=True)
                    continue
                output.parent.mkdir(parents=True, exist_ok=True)
                with bundle.open(item) as source, output.open("wb") as stream:
                    shutil.copyfileobj(source, stream)
                output.chmod(0o755 if mode & 0o111 else 0o644)
        metadata = json.loads((target / "plugin.json").read_text())
        assert metadata["id"] == plugin["plugin"] and metadata["info"]["version"] == plugin["candidate"]
        assert (target / "MANIFEST.txt").is_file()
        binaries = list(target.glob("*_linux_amd64"))
        assert len(binaries) == 1
        version = subprocess.check_output(["go", "version", str(binaries[0])], text=True)
        assert version.rstrip().endswith(" " + plugin["compiled_go"]), version
        print(plugin["plugin"], plugin["candidate"], plugin["compiled_go"], flush=True)
