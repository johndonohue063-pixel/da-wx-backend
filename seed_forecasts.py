import os, sqlite3, requests, time

DB = os.getenv("WX_DB_PATH", r"C:\Divergent\wx_backend\wx_backend.db")
NE = {"ME","NH","VT","MA","RI","CT","NY","NJ","PA","DE"}

con = sqlite3.connect(DB)
cur = con.cursor()
cur.execute("SELECT fips, state, lat, lon FROM counties")
rows = cur.fetchall()
con.close()

todo = [(f,s,lat,lon) for f,s,lat,lon in rows if s in NE]
print(f"Seeding {len(todo)} counties via /forecast/point ...")

ok = 0; fail = 0
for fips, state, lat, lon in todo:
    try:
        r = requests.get("http://127.0.0.1:8010/forecast/point",
                         params={"lat": lat, "lon": lon}, timeout=30)
        r.raise_for_status()
        ok += 1
    except Exception as e:
        fail += 1
    time.sleep(0.20)  # be polite to api.weather.gov
print(f"done. ok={ok} fail={fail}")
