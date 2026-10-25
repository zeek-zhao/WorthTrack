#!/usr/bin/env python3
import json
import urllib.request

TOKEN = open('/home/zeek.zhao/.config/worthtrack/gh_token').read().strip()
BASE = 'https://api.github.com/repos/zeek-zhao/WorthTrack'
H = {'Authorization': 'Bearer ' + TOKEN, 'Accept': 'application/vnd.github+json'}


def get(path):
    req = urllib.request.Request(BASE + path, headers=H)

    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, *a, **k):
            return None

    opener = urllib.request.build_opener(NoRedirect)
    try:
        return opener.open(req).read()
    except urllib.error.HTTPError as e:
        if e.status in (301, 302, 303, 307):
            return urllib.request.urlopen(urllib.request.Request(e.headers['Location'])).read()
        raise


jobs = json.loads(get('/actions/runs/40177437014/jobs').decode())
log = get('/actions/jobs/%d/logs' % jobs['jobs'][0]['id']).decode('utf-8', 'replace')
for l in log.splitlines():
    low = l.lower()
    if ('determine flutter' in low or 'flutter version' in low or
            'storage.googleapis' in low or 'is cached' in low or
            'cache hit' in low or 'cache not found' in low or
            'run dart/flutter pub get' in low or 'pub get' in low or
            'version: ' in low and 'flutter' in low):
        print(l[:280])
