"""Run ONLY in a disposable root container with /source mounted read-only.

Exercises real dpkg unpack/configure/remove and filesystem permissions; PostgreSQL,
systemd, API and the CPU-specific executable are mocked. Never run on a real Pi.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import unittest

SOURCE = Path("/source")
WORK = Path("/tmp/replab-package-test")
STATE = WORK / "state.json"
PACKAGE = SOURCE / "build/replab-server_0.6.2-1_arm64.deb"
APP = Path("/opt/replab/replab-server")
RUNTIME = Path("/etc/replab/runtime.env")
OWNER = Path("/etc/replab/owner.env")

MOCK = r'''#!/usr/bin/python3
import json, os, pathlib, sys
p = pathlib.Path("/tmp/replab-package-test/state.json")
s = json.loads(p.read_text())
cmd, args = pathlib.Path(sys.argv[0]).name, sys.argv[1:]
s["events"].append([cmd, *args])
def save(): p.write_text(json.dumps(s))
def quit(code=0): save(); sys.exit(code)
if cmd == "sleep": quit()
if cmd == "systemctl":
    if args[0] == "cat": print("[Service]\nExecStart=/opt/replab/replab-server serve")
    if "replab.service" in args:
        if args[0] in ("stop", "disable"): s["active"] = False
        if args[0] == "enable": s["active"] = True
    quit()
if cmd == "curl":
    assert "--cacert" in args and "--resolve" in args and "--noproxy" in args
    assert "--insecure" not in args and "-k" not in args
    assert args[-1].endswith(":8443/health/ready")
    if s.get("fail_health") or not s["active"] or s["schema"] != 4: quit(22)
    print('{"status":"ready","database":"ok","schema":"4"}'); quit()
if cmd == "runuser":
    assert os.environ["PGHOST"] == "/var/run/postgresql"
    assert os.environ["PGPORT"] == "5432" and os.environ["PGUSER"] == "postgres"
    args = args[args.index("--")+1:]
    command, args = args[0], args[1:]
    if command == "pg_dump":
        if s.get("fail_backup"): quit(1)
        sys.stdout.write("PGDMP synthetic disposable fixture"); quit()
    if command in ("createdb", "dropdb"):
        assert args[0].startswith("restore_check_")
        quit()
    if command == "pg_restore":
        assert sys.stdin.buffer.read().startswith(b"PGDMP")
        quit(1 if s.get("fail_restore") else 0)
    assert command == "psql"
    query = args[args.index("-c")+1] if "-c" in args else sys.stdin.read()
    if "CREATE ROLE" in query:
        s["database"] = True; s["roles"] = 2
    elif "SELECT count(*) FROM admins" in query: print(s["admins"])
    elif "to_regclass('public.replab_schema')" in query and "-c" in args:
        print("t" if s["schema"] else "f")
    elif "::text || '|'" in query:
        print(("true" if s["database"] else "false") + "|" + str(s["roles"]))
    elif "SELECT EXISTS" in query:
        print("t" if s["database"] or s["roles"] else "f")
    quit()
if cmd == "replab-server":
    if args == ["--version"]: print("replab-server 0.6.2")
    elif args[0] == "configure":
        directory = pathlib.Path("/etc/replab")
        common = "POSTGRES_HOST=127.0.0.1\nPOSTGRES_PORT=5432\nPOSTGRES_DB=replab\n"
        (directory/"owner.env").write_text(common + "POSTGRES_USER=replab_owner\nPOSTGRES_PASSWORD=synthetic-owner\n")
        (directory/"runtime.env").write_text(common + "POSTGRES_USER=replab_app\nPOSTGRES_PASSWORD=synthetic-runtime\nALLOWED_HOSTS=localhost,127.0.0.1,fixture.local\nTLS_CERT_PATH=/etc/replab/server.crt\nTLS_KEY_PATH=/etc/replab/server.key\nCORS_ORIGINS=\n")
        (directory/"owner.env").chmod(0o600)
        (directory/"runtime.env").chmod(0o600)
    elif args[-1] == "migrate":
        if s.get("fail_migration"): quit(1)
        s["schema"] = 4
    elif args[-1] == "create-admin":
        assert s["admins"] == 0
        s["admins"] = 1
    else: raise AssertionError(args)
    quit()
raise AssertionError((cmd, args))
'''


class InstallerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        assert os.geteuid() == 0 and Path("/.dockerenv").exists()
        assert os.environ.get("REPLAB_DISPOSABLE_INSTALL_TEST") == "1"
        assert os.statvfs(SOURCE).f_flag & os.ST_RDONLY
        assert PACKAGE.is_file()
        WORK.mkdir(exist_ok=True)
        (WORK / "bin").mkdir(exist_ok=True)
        (WORK / "mock").write_text(MOCK)
        (WORK / "mock").chmod(0o755)
        for name in ["systemctl", "runuser", "curl", "sleep"]:
            (WORK / "bin" / name).symlink_to(WORK / "mock")
        cls.env = {**os.environ, "PATH": f"{WORK}/bin:" + os.environ["PATH"]}
        subprocess.run(["adduser", "--system", "--group", "--no-create-home", "replab"], check=True)
        Path("/run/systemd/system").mkdir(parents=True, exist_ok=True)
        root_mode = Path("/").stat().st_mode & 0o777
        subprocess.run(["dpkg", "--force-architecture", "--unpack", str(PACKAGE)], check=True)
        assert Path("/").stat().st_mode & 0o777 == root_mode
        # Replace ONLY this disposable container's CPU-specific candidate.
        Path("/usr/lib/replab/replab-server").write_text(MOCK)
        Path("/usr/lib/replab/replab-server").chmod(0o755)
        # Reuse a real certificate so ownership/permissions and secret copies
        # are checked without doing RSA key generation for every failure test.
        (WORK / "certs").mkdir(exist_ok=True)
        subprocess.run(["sh", str(SOURCE / "tools/create-cert.sh"), "fixture.local", str(WORK / "certs")],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def setUp(self):
        for path in [Path("/etc/replab"), Path("/opt/replab"), Path("/var/backups/replab"), Path("/var/lib/replab-client")]:
            if path.exists():
                shutil.rmtree(path)  # Fixed test-owned paths, disposable container only.
        self.write_state(database=False, roles=0, schema=0, admins=0, active=False, events=[],
                         session="synthetic-saved-session", receipt={"amount_paise":1010000})

    def write_state(self, **fields):
        STATE.write_text(json.dumps(fields))

    def state(self):
        return json.loads(STATE.read_text())

    def run_installer(self, action="configure", command=None):
        return subprocess.run(command or ["sh", "/usr/lib/replab/install-host.sh", action],
                              env=self.env, capture_output=True, text=True)

    def existing(self):
        directory = Path("/etc/replab")
        certs = directory / "hostname-v0.4.1"
        certs.mkdir(parents=True)
        for name in ["server.crt", "server.key"]:
            shutil.copy2(WORK / "certs" / name, certs / name)
        common = "POSTGRES_HOST=127.0.0.1\nPOSTGRES_PORT=5432\nPOSTGRES_DB=replab\n"
        OWNER.write_text(common + "POSTGRES_USER=replab_owner\nPOSTGRES_PASSWORD=keep-owner\n")
        RUNTIME.write_text(common + "POSTGRES_USER=replab_app\nPOSTGRES_PASSWORD=keep-app\n"
                           "ALLOWED_HOSTS=fixture.local\nCORS_ORIGINS=http://localhost:8080\n"
                           "TLS_CERT_PATH=/etc/replab/hostname-v0.4.1/server.crt\n"
                           "TLS_KEY_PATH=/etc/replab/hostname-v0.4.1/server.key\n")
        OWNER.chmod(0o600)
        RUNTIME.chmod(0o640)
        APP.parent.mkdir(parents=True)
        APP.write_bytes(b"the-previous-v0.4.1-executable")
        APP.chmod(0o755)
        self.old_files = {p: p.read_bytes() for p in [OWNER, RUNTIME, certs/"server.crt", certs/"server.key"]}
        state = self.state()
        state.update(database=True, roles=2, schema=3, admins=1, active=True)
        self.write_state(**state)

    def assert_preserved(self):
        for path, content in self.old_files.items():
            self.assertEqual(path.read_bytes(), content)
        self.assertEqual(self.state()["session"], "synthetic-saved-session")
        self.assertEqual(self.state()["receipt"], {"amount_paise":1010000})

    def test_dpkg_fresh_configure_and_initial_admin(self):
        result = self.run_installer(command=["dpkg", "--force-depends", "--configure", "replab-server:arm64"])
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertTrue(self.state()["active"])
        self.assertEqual(self.state()["schema"], 4)
        self.assertEqual(self.state()["admins"], 0)
        self.assertIn("sudo replab-setup", result.stdout)
        self.assertEqual(OWNER.stat().st_mode & 0o777, 0o600)
        self.assertEqual(RUNTIME.stat().st_mode & 0o777, 0o640)
        self.assertEqual(Path("/etc/replab/server.key").stat().st_mode & 0o777, 0o640)
        self.assertEqual(Path("/var/lib/replab-client/server.crt").stat().st_mode & 0o777, 0o644)
        self.assertEqual(self.run_installer("admin").returncode, 0)
        self.assertEqual(self.state()["admins"], 1)
        self.assertIn("already has", self.run_installer("admin").stdout)

    def test_existing_upgrade_preserves_and_verifies_before_migration(self):
        self.existing()
        result = self.run_installer()
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assert_preserved()
        self.assertTrue(self.state()["active"])
        backups = list(Path("/var/backups/replab").glob("install-*"))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].stat().st_mode & 0o777, 0o700)
        self.assertEqual((backups[0]/"application/replab-server").read_bytes(), b"the-previous-v0.4.1-executable")
        self.assertTrue((backups[0]/"database.dump").read_bytes().startswith(b"PGDMP"))
        events = self.state()["events"]
        restored = next(i for i, e in enumerate(events) if e[0] == "runuser" and "pg_restore" in e)
        migrated = next(i for i, e in enumerate(events) if e[0] == "replab-server" and "migrate" in e)
        self.assertLess(restored, migrated)
        # A repeated package configuration never rotates keys or creates admins.
        self.assertEqual(self.run_installer().returncode, 0)
        self.assert_preserved()
        self.assertEqual(self.state()["admins"], 1)

    def test_failed_backup_or_restore_keeps_old_executable_and_stops_api(self):
        for failure in ["fail_backup", "fail_restore"]:
            with self.subTest(failure=failure):
                self.setUp()
                self.existing()
                state = self.state()
                state[failure] = True
                self.write_state(**state)
                self.assertNotEqual(self.run_installer().returncode, 0)
                self.assertFalse(self.state()["active"])
                self.assertEqual(APP.read_bytes(), b"the-previous-v0.4.1-executable")
                self.assert_preserved()
                self.assertFalse(any("migrate" in e for e in self.state()["events"]))

    def test_failed_migration_or_health_never_restores_or_restarts_old_schema(self):
        for failure in ["fail_migration", "fail_health"]:
            with self.subTest(failure=failure):
                self.setUp()
                self.existing()
                state = self.state()
                state[failure] = True
                self.write_state(**state)
                self.assertNotEqual(self.run_installer().returncode, 0)
                self.assertFalse(self.state()["active"])
                self.assert_preserved()
                self.assertTrue(list(Path("/var/backups/replab").glob("install-*/database.dump")))
                self.assertEqual(self.state()["schema"], 3 if failure == "fail_migration" else 4)

    def test_partial_config_and_unrelated_database_are_refused(self):
        self.existing()
        OWNER.unlink()
        self.assertNotEqual(self.run_installer().returncode, 0)
        self.assertTrue(self.state()["active"])  # Preflight failed before stopping.
        self.assertFalse(OWNER.exists())
        self.setUp()
        state = self.state()
        state.update(database=True, roles=2, schema=3, admins=1)
        self.write_state(**state)
        self.assertNotEqual(self.run_installer().returncode, 0)
        self.assertFalse(RUNTIME.exists())
        self.assertFalse(OWNER.exists())

    def test_retry_initial_setup_keeps_generated_secrets_and_certificate(self):
        state = self.state()
        state["fail_migration"] = True
        self.write_state(**state)
        self.assertNotEqual(self.run_installer().returncode, 0)
        paths = [OWNER, RUNTIME, Path("/etc/replab/server.crt"), Path("/etc/replab/server.key")]
        saved = {path: path.read_bytes() for path in paths}
        state = self.state()
        state["fail_migration"] = False
        self.write_state(**state)
        self.assertEqual(self.run_installer().returncode, 0)
        for path, content in saved.items():
            self.assertEqual(path.read_bytes(), content)
        self.assertFalse(Path("/etc/replab/.package-initializing").exists())

    def test_nonlocal_or_mismatched_database_settings_fail_before_stopping(self):
        for old, new in [("POSTGRES_HOST=127.0.0.1", "POSTGRES_HOST=192.168.1.50"),
                         ("POSTGRES_PORT=5432", "POSTGRES_PORT=5433"),
                         ("POSTGRES_DB=replab", "POSTGRES_DB=another_database")]:
            with self.subTest(setting=new):
                self.setUp()
                self.existing()
                RUNTIME.write_text(RUNTIME.read_text().replace(old, new))
                self.assertNotEqual(self.run_installer().returncode, 0)
                self.assertTrue(self.state()["active"])
                self.assertEqual(APP.read_bytes(), b"the-previous-v0.4.1-executable")
                self.assertFalse(Path("/var/backups/replab").exists())

    def test_z_dpkg_remove_retains_database_config_and_backups(self):
        self.existing()
        self.assertEqual(self.run_installer().returncode, 0)
        result = self.run_installer(command=["dpkg", "--remove", "replab-server:arm64"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.state()["active"])
        self.assertTrue(APP.exists())
        self.assertTrue(list(Path("/var/backups/replab").glob("install-*/database.dump")))
        self.assert_preserved()


if __name__ == "__main__":
    unittest.main(verbosity=2)
