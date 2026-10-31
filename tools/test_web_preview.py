from pathlib import Path
import tempfile
import unittest

from web_preview import source_snapshot


class SourceSnapshotTest(unittest.TestCase):
    def test_detects_dart_and_asset_edits_but_ignores_build_output(self):
        with tempfile.TemporaryDirectory() as directory:
            tablet = Path(directory)
            for folder in ("lib", "assets", "build"):
                (tablet / folder).mkdir()
            dart = tablet / "lib" / "main.dart"
            dart.write_text("first")
            before = source_snapshot(tablet)
            dart.write_text("changed source")
            after = source_snapshot(tablet)
            self.assertNotEqual(before, after)
            (tablet / "build" / "output.js").write_text("compiled")
            self.assertEqual(after, source_snapshot(tablet))
            asset = tablet / "assets" / "icon.svg"
            asset.write_text("<svg/>")
            self.assertNotEqual(after, source_snapshot(tablet))
            asset.unlink()
            self.assertEqual(after, source_snapshot(tablet))
            dart.unlink()
            self.assertEqual({}, source_snapshot(tablet))


if __name__ == "__main__":
    unittest.main()
