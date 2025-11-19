from datetime import date
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse

app = FastAPI(title="Divergent API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"], allow_methods=["*"], allow_headers=["*"],
)

@app.get("/health")
def health():
    return {"status": "ok"}

@app.get("/api/weather")
def api_weather(region: str, state: str, start: date, end: date, wind: int = 0):
    days = (end - start).days + 1
    return {
        "region": region, "state": state,
        "start": str(start), "end": str(end),
        "wind_max": wind, "days": days,
        "summary": f"{state} ({region}) {start}→{end}, wind≤{wind} mph, {days} days"
    }

@app.get("/app/", response_class=HTMLResponse)
def maps_page():
    return """<!doctype html>
<html><head><meta charset="utf-8"><title>Weather Maps</title></head>
<body style="background:#000;color:#fff;font-family:system-ui;display:grid;place-items:center;height:100vh">
  <div>
    <h1>Weather Maps (demo)</h1>
    <p>Hash route: <code>#/storm</code></p>
  </div>
</body></html>"""
