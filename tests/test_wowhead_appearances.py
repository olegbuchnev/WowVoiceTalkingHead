import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch
import tempfile
import json
import urllib.error

spec = importlib.util.spec_from_file_location('appearances', Path(__file__).resolve().parents[1] / 'tools/fill-wowhead-appearances.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class AppearanceEvidenceTests(unittest.TestCase):
    url = 'https://www.wowhead.com/forever/ru/npc=918'
    page = '''<link rel="canonical" href="https://www.wowhead.com/forever/ru/npc=918/name">
    <script>linksButton.dataset.displayId = 1507;</script>
    <a data-mv-type="1" data-mv-type-id="918" data-mv-display-id="1507"></a>
    <h1>Осборн Дитя Ночи &lt;Наставник разбойников&gt;</h1>'''

    def test_localized_name_and_model(self):
        result = module.parse_page(918, self.page, self.url)
        self.assertEqual(result['displayID'], 1507)
        self.assertEqual(result['nameRu'], 'Осборн Дитя Ночи')

    def test_wrong_identity_or_edition(self):
        for page, url in [(self.page.replace('npc=918/', 'npc=919/'), self.url),
                          (self.page, self.url.replace('/forever', '')),
                          (self.page.replace('type-id="918"', 'type-id="919"'), self.url)]:
            with self.subTest(url=url, page=page), self.assertRaises(ValueError):
                module.parse_page(918, page, url)

    def test_missing_or_conflicting_display(self):
        for page in [self.page.replace('= 1507;', '= 1508;'),
                     self.page.replace('display-id="1507"', 'display-id="0"'),
                     self.page + '<a data-mv-type="1" data-mv-type-id="918" data-mv-display-id="1508"></a>']:
            with self.subTest(page=page), self.assertRaises(ValueError):
                module.parse_page(918, page, self.url)

    def test_no_invented_translation(self):
        result = module.parse_page(918, self.page.replace('Осборн Дитя Ночи', 'Osborne'), self.url)
        self.assertNotIn('nameRu', result)

    def test_challenge_is_not_an_npc(self):
        with self.assertRaises(ValueError):
            module.parse_page(918, '<h1>Just a moment...</h1>', self.url)

    def test_block_on_last_npc_still_fails_the_pass(self):
        with tempfile.TemporaryDirectory() as directory, \
                patch.object(module, 'CACHE', Path(directory)), \
                patch.object(module, 'candidates', return_value=[{'npcID':918}]), \
                patch.object(module.time, 'sleep'), \
                patch.object(module.urllib.request, 'urlopen', side_effect=urllib.error.HTTPError(self.url,429,'Rate limit',None,None)), \
                patch('sys.argv', ['fill-wowhead-appearances.py']):
            with self.assertRaises(SystemExit) as result:
                module.run()
            self.assertEqual(result.exception.code,1)
            report=json.loads((Path(directory)/'voting-report.json').read_text(encoding='utf-8'))
            self.assertFalse(report['completed'])
            self.assertEqual(report['results'][0]['status'],'blocked')


if __name__ == '__main__':
    unittest.main()
