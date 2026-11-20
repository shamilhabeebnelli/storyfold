import json
from pathlib import Path
import subprocess
import threading
import unittest
import urllib.error
import urllib.request
import app

class Tests(unittest.TestCase):
    def test_rss(self):
        rows=app.parse_feed(b'<rss><channel><title>Daily</title><item><title>News</title><link>https://example.com</link><description>Body</description></item></channel></rss>')
        self.assertEqual(rows[0]['source'],'Daily'); self.assertEqual(rows[0]['body'],'Body')
    def test_atom(self):
        rows=app.parse_feed(b'<feed xmlns="http://www.w3.org/2005/Atom"><title>Atom</title><entry><title>Story</title><link rel="self" href="self"/><link href="https://example.com/a"/><updated>2026-11-20</updated><summary>Hello</summary></entry></feed>')
        self.assertEqual(rows[0]['url'],'https://example.com/a')
    def test_dtd(self):
        with self.assertRaises(ValueError): app.parse_feed(b'<!DOCTYPE rss><rss/>')
    def test_bad_xml(self):
        with self.assertRaises(Exception): app.parse_feed(b'<rss>')
    def test_field_type(self):
        with self.assertRaises(ValueError): app.validate_articles([{'title':123}])
    def test_count_limit(self):
        with self.assertRaises(ValueError): app.validate_articles([{'title':'x'}]*501)
    def test_body_limit(self):
        with self.assertRaises(ValueError): app.validate_articles([{'title':'x','body':'a'*10001}])
    def test_threshold(self):
        with self.assertRaises(ValueError): app.group([],True)
    def test_sample(self):
        report=app.group(json.loads((Path(__file__).parent/'sample.json').read_text()))
        self.assertEqual(report['inputCount'],6); self.assertEqual(len(report['groups']),4)
    def test_json_unicode_and_escaping(self):
        a={'title':'മലയാളം "quoted"\n<script>','url':'https://example.com/','body':'\\'}
        report=app.group([a]); self.assertEqual(report['groups'][0]['lead']['title'],a['title'])
    def test_engine_malformed(self):
        r=subprocess.run([str(app.ROOT/'storyfold')],input='xyz\n',text=True,capture_output=True)
        self.assertNotEqual(r.returncode,0)
    def test_server_host_and_token(self):
        server=app.HTTPServer(('127.0.0.1',0),app.Handler)
        thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
        base='http://127.0.0.1:'+str(server.server_port)
        try:
            with urllib.request.urlopen(base) as r: self.assertIn(app.TOKEN,r.read().decode())
            req=urllib.request.Request(base+'/group',data=b'{"articles":[]}')
            with self.assertRaises(urllib.error.HTTPError) as error: urllib.request.urlopen(req)
            self.assertEqual(error.exception.code,403)
            req=urllib.request.Request(base+'/group',data=b'{"articles":[]}',headers={'X-StoryFold-Token':app.TOKEN})
            with urllib.request.urlopen(req) as r: self.assertEqual(json.load(r)['inputCount'],0)
            req=urllib.request.Request(base,headers={'Host':'evil.example'})
            with self.assertRaises(urllib.error.HTTPError) as error: urllib.request.urlopen(req)
            self.assertEqual(error.exception.code,403)
        finally: server.shutdown();server.server_close();thread.join()

if __name__=='__main__': unittest.main()
