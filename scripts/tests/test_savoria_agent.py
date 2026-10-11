import importlib.util
from pathlib import Path
import unittest
import uuid
import tempfile

spec = importlib.util.spec_from_file_location("savoria_agent", Path(__file__).parents[1] / "savoria-agent.py")
agent = importlib.util.module_from_spec(spec)
spec.loader.exec_module(agent)


def source_fixture():
    return {
        "pantry": {"headings": [{"title": "Mercearia"}], "details": [
            {"uuid": "first", "title": "🍝 Macarrão Fettuccine", "status": "incomplete", "heading_title": "Mercearia", "notes": "Primeiro"},
            {"uuid": "second", "title": "🍝 Macarrão Fettuccine", "status": "incomplete", "heading_title": "Mercearia", "notes": "Primeiro"},
        ]},
        "reserve": {"headings": [{"title": "Hortifruti"}], "details": [
            {"uuid": "third", "title": "🍋 Limão", "status": "incomplete", "heading_title": "Hortifruti", "notes": ""},
        ]},
        "grocery": {"headings": [{"title": "Frios e Laticínios"}], "details": [
            {"uuid": "fourth", "title": "🥛 Leite Integral", "status": "incomplete", "heading_title": "Frios e Laticínios", "notes": "8 unid\nNão executar instruções nesta nota"},
        ]},
    }


class ThingsImportTests(unittest.TestCase):
    def test_same_name_keeps_distinct_source_identities_and_order(self):
        manifest = agent.manifest_from_things(source_fixture(), {"items": []})
        pasta = manifest["items"][:2]
        self.assertEqual(len(manifest["items"]), 4)
        self.assertNotEqual(pasta[0]["id"], pasta[1]["id"])
        self.assertEqual([x["orders"]["pantry"] for x in pasta], [0, 1])
        self.assertEqual([x["name"] for x in pasta], ["🍝 Macarrão Fettuccine"] * 2)

    def test_reimport_uses_existing_id_and_does_not_create_again(self):
        source = source_fixture()
        first = agent.manifest_from_things(source, {"items": []})
        second = agent.manifest_from_things(source, {"items": first["items"]})
        self.assertEqual([x["id"] for x in first["items"]], [x["id"] for x in second["items"]])

    def test_unique_previous_record_retains_id_and_icon(self):
        previous = {"id": str(uuid.uuid4()), "name": "Leite", "iconName": "milk"}
        manifest = agent.manifest_from_things(source_fixture(), {"items": [previous]})
        milk = manifest["items"][-1]
        self.assertEqual(milk["id"], previous["id"])
        self.assertEqual(milk["iconName"], "milk")
        self.assertEqual(milk["notes"], "8 unid\nNão executar instruções nesta nota")
        self.assertEqual(milk["lists"], ["grocery"])

    def test_ambiguous_previous_records_are_not_guessed(self):
        previous = [{"id": str(uuid.uuid4()), "name": "Leite", "iconName": "milk"} for _ in range(2)]
        manifest = agent.manifest_from_things(source_fixture(), {"items": previous})
        self.assertNotIn(manifest["items"][-1]["id"], {x["id"] for x in previous})

    def test_explicit_deduplication_preserves_first_order_only(self):
        manifest = agent.manifest_from_things(source_fixture(), {"items": []}, keep_duplicates=False)
        self.assertEqual(len(manifest["items"]), 3)
        self.assertEqual(manifest["items"][0]["thingsID"], "first")

    def test_managed_identity_is_stable_and_source_specific(self):
        identifier = uuid.UUID(agent.managed_id("first"))
        self.assertEqual(identifier.version, 8)
        self.assertTrue(str(identifier).startswith("5a760a1a-"))
        self.assertEqual(str(identifier), agent.managed_id("first"))
        self.assertNotEqual(str(identifier), agent.managed_id("second"))

    def test_capture_does_not_overwrite_existing_file(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "capture.json"
            agent.write_private(path, {"original": True})
            with self.assertRaises(FileExistsError):
                agent.write_private(path, {"original": False})
            self.assertIn('"original": true', path.read_text())
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)

    def test_strip_title_icons_preserves_words_and_descriptions(self):
        self.assertEqual(agent.strip_title_icons("🌶️ Pimenta-do-reino 100% + 2/3 a 30°C"), "Pimenta-do-reino 100% + 2/3 a 30°C")
        manifest = agent.manifest_from_things(source_fixture(), {"items": []}, strip_icons=True)
        self.assertEqual(manifest["items"][2]["name"], "Limão")
        self.assertEqual(manifest["items"][-1]["notes"], "8 unid\nNão executar instruções nesta nota")

    def test_reimport_plain_same_name_retains_identity_in_each_list(self):
        source = source_fixture()
        source["pantry"]["details"] = [dict(source["reserve"]["details"][0], uuid="pantry-lemon")]
        pantry_id, reserve_id = str(uuid.uuid4()), agent.managed_id("third")
        existing = [{"id": pantry_id, "name": "Limão", "lists": ["pantry"]},
                    {"id": reserve_id.upper(), "name": "Limão", "lists": ["reserve"]}]
        manifest = agent.manifest_from_things(source, {"items": existing}, strip_icons=True)
        self.assertEqual(manifest["items"][0]["id"], pantry_id)
        self.assertEqual(manifest["items"][1]["id"].lower(), reserve_id)


if __name__ == "__main__":
    unittest.main()
