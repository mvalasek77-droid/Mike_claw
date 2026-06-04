#!/usr/bin/env python3
"""
ASC API Setup - Registers Bundle ID + App record + enables Xcode Cloud
Run with: python3 asc_setup.py <ISSUER_ID>

Requires:
- Issuer ID from App Store Connect > Integrations > App Store Connect API
- AuthKey_N8LHKCW7K8.p8 in ~/private_keys/
"""

import sys, time, json, requests

KEY_ID = 'N8LHKCW7K8'
PRIVATE_KEY_PATH = '/Users/clawcl/private_keys/AuthKey_N8LHKCW7K8.p8'
TEAM_ID = 'UDM4W27W9V'
BUNDLE_ID = 'com.valasek.AIMarketplace'

def get_jwt(issuer_id):
    import jwt
    with open(PRIVATE_KEY_PATH) as f:
        private_key = f.read()
    now = int(time.time())
    payload = {
        'iss': issuer_id,
        'iat': now,
        'exp': now + 1200,  # 20 min
        'aud': 'appstoreconnect-v1',
    }
    headers = {'alg': 'ES256', 'kid': KEY_ID, 'typ': 'JWT'}
    return jwt.encode(payload, private_key, algorithm='ES256', headers=headers)

def asc_get(token, path):
    r = requests.get(f'https://api.appstoreconnect.apple.com/v1{path}',
                     headers={'Authorization': f'Bearer {token}'})
    return r.json(), r.status_code

def asc_post(token, path, data):
    r = requests.post(f'https://api.appstoreconnect.apple.com/v1{path}',
                      headers={'Authorization': f'Bearer {token}',
                               'Content-Type': 'application/json'},
                      json=data)
    return r.json(), r.status_code

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 asc_setup.py <ISSUER_ID>")
        sys.exit(1)
    
    issuer_id = sys.argv[1]
    token = get_jwt(issuer_id)
    
    print(f"JWT generated for issuer {issuer_id}")
    
    # Step 1: Check if bundle ID exists
    resp, status = asc_get(token, '/bundleIds')
    print(f"\nBundle IDs: status={status}")
    if status == 200:
        existing = resp.get('data', [])
        for b in existing:
            bid = b['attributes'].get('identifier', '')
            print(f"  Found: {bid} (id: {b['id']})")
            if bid == BUNDLE_ID:
                print(f"  ✅ {BUNDLE_ID} already registered!")
                bundle_id_resource = b['id']
                break
        else:
            bundle_id_resource = None
    else:
        print(f"  Error: {json.dumps(resp, indent=2)[:500]}")
        bundle_id_resource = None
    
    # Step 2: Register bundle ID if needed
    if not bundle_id_resource:
        print(f"\nRegistering {BUNDLE_ID}...")
        resp, status = asc_post(token, '/bundleIds', {
            'data': {
                'type': 'bundleIds',
                'attributes': {
                    'identifier': BUNDLE_ID,
                    'name': 'AI Marketplace',
                    'platform': 'IOS',
                }
            }
        })
        if status in (200, 201):
            bundle_id_resource = resp['data']['id']
            print(f"  ✅ Registered: {BUNDLE_ID} (id: {bundle_id_resource})")
        else:
            print(f"  Error {status}: {json.dumps(resp, indent=2)[:500]}")
    
    # Step 3: Check if app exists
    resp, status = asc_get(token, '/apps')
    print(f"\nApps: status={status}")
    app_resource = None
    if status == 200:
        for a in resp.get('data', []):
            bid = a['attributes'].get('bundleId', '')
            print(f"  Found: {a['attributes'].get('name', '')} ({bid})")
            if bid == BUNDLE_ID:
                print(f"  ✅ App already exists!")
                app_resource = a['id']
                break
    
    # Step 4: Create app if needed
    if not app_resource and bundle_id_resource:
        print(f"\nCreating app record for {BUNDLE_ID}...")
        resp, status = asc_post(token, '/apps', {
            'data': {
                'type': 'apps',
                'attributes': {
                    'name': 'AI Marketplace',
                    'bundleId': BUNDLE_ID,
                    'primaryLocale': 'en-US',
                    'sku': 'aimarketplace-001',
                }
            }
        })
        if status in (200, 201):
            app_resource = resp['data']['id']
            print(f"  ✅ App created! (id: {app_resource})")
        else:
            print(f"  Error {status}: {json.dumps(resp, indent=2)[:500]}")
    
    # Step 5: Check Xcode Cloud (ciProducts)
    if app_resource:
        print(f"\nChecking Xcode Cloud for app {app_resource}...")
        resp, status = asc_get(token, f'/ciProducts?filter[app]={app_resource}')
        print(f"  CI Products: status={status}")
        if status == 200:
            products = resp.get('data', [])
            if products:
                print(f"  ✅ Xcode Cloud already enabled!")
            else:
                print(f"  No CI products yet — need to create via ASC web UI")
                print(f"  URL: https://appstoreconnect.apple.com/apps/{app_resource}/testflight/xcodecloud")
        else:
            print(f"  {json.dumps(resp, indent=2)[:500]}")
    
    print("\n=== SETUP SUMMARY ===")
    if bundle_id_resource:
        print(f"Bundle ID: ✅ {BUNDLE_ID} ({bundle_id_resource})")
    if app_resource:
        print(f"App Record: ✅ AI Marketplace ({app_resource})")
    else:
        print(f"App Record: ❌ needs manual creation")
    print(f"\nNext step: Open Xcode → Create Xcode Cloud workflow")
    print(f"Or: https://appstoreconnect.apple.com/apps/{app_resource}/testflight/xcodecloud")

if __name__ == '__main__':
    main()