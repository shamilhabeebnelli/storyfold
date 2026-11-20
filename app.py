#!/usr/bin/env python3
"""StoryFold local UI adapter. Haskell owns all grouping decisions."""
import argparse
import json
import os
from pathlib import Path
import secrets
import subprocess
import sys
import xml.etree.ElementTree as ET
from http.server import BaseHTTPRequestHandler, HTTPServer

ROOT = Path(__file__).resolve().parent
TOKEN = secrets.token_urlsafe(32)
LIMIT = 4_000_000


def text(element):
    return ''.join(element.itertext()).strip() if element is not None else ''


def parse_feed(raw, fallback='Imported feed'):
    # No DTD/entity expansion, external resources or XInclude processing.
    if b'<!DOCTYPE' in raw.upper() or b'<!ENTITY' in raw.upper():
        raise ValueError('DTD/entity declarations are not accepted')
    root = ET.fromstring(raw)
    def tag(e): return e.tag.rsplit('}', 1)[-1]
    def first(e, name): return next((x for x in e if tag(x) == name), None)
    channel = first(root, 'channel') if tag(root) == 'rss' else root
    if channel is None or tag(root) not in ('rss', 'feed', 'RDF'):
        raise ValueError('Expected RSS 2.0 or Atom XML')
    source = text(first(channel, 'title')) or fallback
    articles = []
    for entry in channel:
        if tag(entry) not in ('item', 'entry'): continue
        title = text(first(entry, 'title'))
        if not title: continue
        link = first(entry, 'link')
        if tag(entry) == 'entry':
            link = next((x for x in entry if tag(x) == 'link' and x.get('rel', 'alternate') == 'alternate'), None)
        url = (link.get('href', '') or text(link)) if link is not None else ''
        date = first(entry, 'published')
        if date is None: date = first(entry, 'pubDate')
        if date is None: date = first(entry, 'updated')
        content = first(entry, 'content')
        if content is None: content = first(entry, 'description')
        if content is None: content = first(entry, 'summary')
        articles.append(dict(title=title, url=url, source=source, published=text(date), body=text(content)))
    return articles


def validate_articles(items):
    if not isinstance(items, list) or len(items) > 500:
        raise ValueError('Import must contain at most 500 articles')
    result = []
    for item in items:
        if not isinstance(item, dict): raise ValueError('Each article must be an object')
        article = {}
        for key in ('title', 'url', 'source', 'published', 'body'):
            value = item.get(key, '')
            if not isinstance(value, str): raise ValueError('Article fields must be strings')
            if len(value) > (10000 if key == 'body' else 2000):
                raise ValueError('An article field is too large; body limit 10000 characters')
            article[key] = value
        if not article['title'].strip(): raise ValueError('Every article needs a title')
        result.append(article)
    return result


def group(items, threshold=78):
    articles = validate_articles(items)
    if type(threshold) is not int or not 50 <= threshold <= 100:
        raise ValueError('Threshold must be an integer from 50 to 100')
    def encode(s): return ','.join(format(ord(c), 'x') for c in s)
    data = ''.join('\t'.join(encode(a[k]) for k in ('title','url','source','published','body'))+'\n' for a in articles)
    executable = ROOT / ('storyfold.exe' if os.name == 'nt' else 'storyfold')
    proc = subprocess.run([str(executable), str(threshold)], input=data, text=True,
                          encoding='utf-8', capture_output=True, timeout=20, cwd=ROOT)
    if proc.returncode: raise ValueError(proc.stderr.strip() or 'Haskell engine failed')
    return json.loads(proc.stdout)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_): pass
    def respond(self, status, content, mime='application/json; charset=utf-8'):
        payload = content if isinstance(content, bytes) else json.dumps(content, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header('Content-Type', mime)
        self.send_header('Content-Length', str(len(payload)))
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.send_header('Cache-Control', 'no-store')
        self.send_header('Content-Security-Policy', "default-src 'self'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'self'; img-src 'none'; frame-ancestors 'none'; base-uri 'none'")
        self.end_headers()
        self.wfile.write(payload)
    def valid_host(self):
        return self.headers.get('Host') in ('127.0.0.1:'+str(self.server.server_port), 'localhost:'+str(self.server.server_port))
    def do_GET(self):
        if not self.valid_host(): return self.respond(403, {'error':'Invalid host'})
        if self.path == '/':
            data = (ROOT/'index.html').read_bytes().replace(b'__TOKEN__', TOKEN.encode())
            return self.respond(200, data, 'text/html; charset=utf-8')
        if self.path == '/sample': return self.respond(200, json.loads((ROOT/'sample.json').read_text()))
        return self.respond(404, {'error':'Not found'})
    def do_POST(self):
        if not self.valid_host() or self.headers.get('X-StoryFold-Token') != TOKEN:
            return self.respond(403, {'error':'Open the local StoryFold page first'})
        try:
            size = int(self.headers.get('Content-Length', '0'))
            if not 0 < size <= LIMIT: raise ValueError('Request must be 1 byte to 4 MB')
            raw = self.rfile.read(size)
            if len(raw) != size: raise ValueError('Incomplete request')
            if self.path == '/parse':
                return self.respond(200, validate_articles(parse_feed(raw)))
            if self.path != '/group': return self.respond(404, {'error':'Not found'})
            data = json.loads(raw)
            return self.respond(200, group(data['articles'], data.get('threshold',78)))
        except (ValueError, KeyError, TypeError, ET.ParseError, OSError, subprocess.TimeoutExpired) as exc:
            return self.respond(400, {'error':str(exc)})


def main():
    parser=argparse.ArgumentParser(description='StoryFold local-first reader')
    parser.add_argument('--port', type=int, default=8787)
    args=parser.parse_args()
    if not (ROOT/('storyfold.exe' if os.name == 'nt' else 'storyfold')).exists():
        sys.exit('Build first: ghc -O2 -Wall -Werror Main.hs -o storyfold')
    with HTTPServer(('127.0.0.1',args.port),Handler) as server:
        print('StoryFold: http://127.0.0.1:'+str(server.server_port)+' . Press Ctrl+C to stop.', flush=True)
        server.serve_forever()

if __name__ == '__main__': main()
