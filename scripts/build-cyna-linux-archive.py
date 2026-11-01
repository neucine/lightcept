#!/usr/bin/env python3
"""Cross-build the pinned Cyna imaging archive for a Linux AArch64 corpus run."""

import argparse
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT / "src/engine"
CYNA_ROOT = ROOT / "src"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def pipeline_digest() -> str:
    files = [PACKAGE / "lib.cy", CYNA_ROOT / "cyna.toml", CYNA_ROOT / "lib.cy"]
    files += [ROOT / "toolchains/cyna.lock"]
    for name in ("color", "core", "develop", "pipeline", "raw", "render", "tiff", "assets"):
        files += [path for path in (PACKAGE / name).rglob("*") if path.is_file() and ".cyna-cache" not in path.parts]
    files += [path for path in (CYNA_ROOT / "project").rglob("*") if path.is_file() and ".cyna-cache" not in path.parts]
    files += [path for path in (CYNA_ROOT / "intent").rglob("*") if path.is_file() and ".cyna-cache" not in path.parts]
    files += [path for path in (CYNA_ROOT / "contract").rglob("*") if path.is_file() and ".cyna-cache" not in path.parts]
    files += [path for path in (CYNA_ROOT / "desktop").rglob("*") if path.is_file() and ".cyna-cache" not in path.parts]
    digest = hashlib.sha256(b"lightcept-native-source-v1\0")
    for path in sorted(files):
        name = path.relative_to(ROOT).as_posix().encode()
        data = path.read_bytes()
        digest.update(len(name).to_bytes(8, "little"))
        digest.update(name)
        digest.update(len(data).to_bytes(8, "little"))
        digest.update(data)
    return digest.hexdigest()


def headers_digest(include: Path) -> str:
    digest = hashlib.sha256()
    for path in sorted(include.rglob("*")):
        if path.is_file():
            name = path.relative_to(include).as_posix().encode()
            digest.update(len(name).to_bytes(8, "little"))
            digest.update(name)
            digest.update(bytes.fromhex(sha256(path)))
    return digest.hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--linux-include", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    include = args.linux_include.resolve()
    assert (include / "aarch64-linux-gnu").is_dir(), "expected Ubuntu ARM64 multiarch headers"
    compiler = ROOT / "target/cyna-toolchain/cyna/zig-out/bin/cyna"
    subprocess.run([str(ROOT / "scripts/check-cyna-toolchain.sh"), str(compiler)], check=True)
    receipt = ROOT / "target/cyna-toolchain/receipt"
    args.output_dir.mkdir(parents=True, exist_ok=True)
    archive = args.output_dir / "liblightcept_cyna_imaging.a"
    with tempfile.TemporaryDirectory(prefix="lightcept-cyna-linux-") as temporary:
        project = Path(temporary)
        shutil.copy2(CYNA_ROOT / "lib.cy", project / "lib.cy")
        (project / "engine").mkdir()
        shutil.copy2(PACKAGE / "lib.cy", project / "engine/lib.cy")
        for name in ("color", "core", "develop", "pipeline", "raw", "render", "tiff"):
            shutil.copytree(PACKAGE / name, project / "engine" / name)
        shutil.copytree(CYNA_ROOT / "project", project / "project")
        shutil.copytree(CYNA_ROOT / "intent", project / "intent")
        shutil.copytree(CYNA_ROOT / "contract", project / "contract")
        shutil.copytree(CYNA_ROOT / "desktop", project / "desktop")
        config = (CYNA_ROOT / "cyna.toml").read_text()
        assert 'target = "native"' in config
        (project / "cyna.toml").write_text(config.replace('target = "native"', 'target = "aarch64-unknown-linux-gnu"'))
        environment = os.environ.copy()
        environment["CPATH"] = os.pathsep.join([str(include), str(include / "aarch64-linux-gnu")])
        subprocess.run([str(compiler), "build", str(project), "--output", str(archive)], cwd=ROOT, env=environment, check=True)
    assert archive.read_bytes().startswith(b"!<arch>\n"), "Cyna did not produce an archive"
    shutil.copyfile(receipt, args.output_dir / "compiler-receipt.txt")
    manifest = {
        "target": "aarch64-unknown-linux-gnu",
        "pipeline_source_sha256": pipeline_digest(),
        "cyna_lock_sha256": sha256(ROOT / "toolchains/cyna.lock"),
        "archive_sha256": sha256(archive),
        "compiler_receipt_sha256": sha256(receipt),
        "linux_headers_sha256": headers_digest(include),
    }
    (args.output_dir / "manifest.txt").write_text("".join(f"{key}={value}\n" for key, value in manifest.items()))


if __name__ == "__main__":
    main()
