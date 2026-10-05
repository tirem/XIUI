import tempfile
from pathlib import Path
import unittest

from update_mob_data import compile_horizon, compile_zone, make_record, merge_attributes, merge_patch, module_roots


class MobDataTests(unittest.TestCase):
    def setUp(self):
        self.species = {"test": ("test_family", {
            "detects": ["sight", "hearing", "lowhp", "scent"],
            "jobs": ["war", "none"],
            "resists": {"dmg_physical": {"slashing": -2500},
                        "rank_element": {"fire": 5}},
        })}
        self.jobs = {"none": 0, "war": 1, "blm": 4}
        self.immunities = {"addle": 1, "light_sleep": 0x800, "dark_sleep": 0x1000}
        self.detects = {"sight": 1, "hearing": 2, "lowhp": 4, "scent": 0x100}

    def test_attribute_inheritance_replaces_lists_and_preserves_other_resists(self):
        merged = merge_attributes({"detects": ["sight"], "resists": {"rank_element": {"fire": 5, "ice": 2}}},
                                  {"detects": [], "resists": {"rank_element": {"fire": 0}}})
        self.assertEqual(merged["detects"], [])
        self.assertEqual(merged["resists"]["rank_element"], {"fire": 0, "ice": 2})

    def test_damage_ranks_immunity_and_true_detection(self):
        template = {"species": "test", "attributes": {
            "behaviors": {"true_detection": True},
            "resists": {"dmg_magic": {"all": -2500, "fire": 2500},
                        "immune_status": ["dark_sleep"]},
        }}
        record = make_record("Test_Mob", template, {}, self.species, self.jobs, self.immunities, self.detects)
        self.assertEqual(record["Modifiers"]["Slashing"], 0.75)
        self.assertEqual(record["Modifiers"]["Fire"], 0.9375)
        self.assertEqual(record["ElementRanks"]["Fire"], 5)
        self.assertEqual(record["Immunities"], 0x1000)
        self.assertTrue(record["TrueSight"] and record["TrueSound"] and record["Blood"] and record["Scent"])
        self.assertFalse(record["Sight"] or record["Sound"])
        self.assertNotIn("MinLevel", record)

    def test_spawn_jobs_and_generic_name_range(self):
        document = {"templates": {"Test_Mob": {"species": "test", "display_name": "Test"}}, "spawns": {
            0x1064001: {"template": "Test_Mob", "level": [10, 12]},
            0x1064002: {"template": "Test_Mob", "level": [14, 15], "attributes": {"jobs": ["blm", "none"]}},
            0x1064003: {"script": "Reserved"},
        }}
        names, indices = compile_zone(document, self.species, self.jobs, self.immunities, self.detects)
        self.assertEqual(indices[2]["Job"], 4)
        self.assertNotIn(3, indices)
        self.assertEqual((names["Test"]["MinLevel"], names["Test"]["MaxLevel"], names["Test"]["Job"]), (10, 15, 0))
        self.assertEqual(names["Test Mob"], names["Test"])

    def test_module_patch_deletes_spawns_and_replaces_arrays(self):
        result = merge_patch({"spawns": {1: {"level": [99, 99], "region": "retail"}, 2: {}}},
                             {"spawns": {1: {"level": [75, 75], "region": None}, 2: None}})
        self.assertEqual(result, {"spawns": {1: {"level": [75, 75]}}})

    def test_horizon_import_keeps_compatibility_fields_only(self):
        names, indices = compile_horizon(r"""return {
    Names = {
        ['Djokvukk\'s Wyvern'] = { Name='Djokvukk\'s Wyvern', Job=1, MinLevel=75, MaxLevel=80, Aggro=true, Modifiers={Fire=1} },
    },
    Indices = {
        [82] = { Name='V. Footsoldier', Job=1, MinLevel=90, MaxLevel=92, Immunities=0 },
    }
};""")
        self.assertEqual(names["Djokvukk's Wyvern"], {"Name": "Djokvukk's Wyvern", "Job": 1, "MinLevel": 75, "MaxLevel": 80})
        self.assertEqual(indices[82]["Name"], "V. Footsoldier")
        self.assertNotIn("Immunities", indices[82])
        with self.assertRaises(ValueError):
            compile_horizon("return os.execute('anything')")

    def test_enabled_module_order_and_no_recursive_parent_loading(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            for path in ("era/data/abyssea", "phoenix/data/limbus", "phoenix/data/dynazones"):
                (root / "modules" / path).mkdir(parents=True)
            (root / "modules/init.txt").write_text(
                "# comment\nera/data\nera/data/abyssea\nphoenix/data/limbus\nphoenix/data/limbus\n")
            self.assertEqual([str(p.relative_to(root)).replace("\\", "/") for p in module_roots(root)],
                             ["modules/era/data", "modules/era/data/abyssea", "modules/phoenix/data/limbus"])


if __name__ == "__main__":
    unittest.main()
