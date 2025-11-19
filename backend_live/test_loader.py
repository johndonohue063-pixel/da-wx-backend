import os, asyncio
import main_cenpop as m

print("CENPOP_PATH =", os.environ.get("CENPOP_PATH"))
async def go():
    await m.load_counties()
    print("COUNTIES =", len(m.COUNTIES))
    print("SAMPLE  =", m.COUNTIES[:3])
asyncio.run(go())
