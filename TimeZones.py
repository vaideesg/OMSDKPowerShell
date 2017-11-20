import pytz
import json
from datetime import datetime
tt = {}
def r(ival):
    sign = "+" if int(ival) >= 0 else "-"
    return sign + u(ival)

def u(ival):
    return ("00" + str(abs(int(ival))))[-2:]

for i in pytz.all_timezones:
    now = datetime.now(pytz.timezone(i))
    ofs = int(now.strftime("%z"))
    #tt[i] = pytz.timezone(i).tzname(datetime.now())

    tt[i] = "GMT%s:%s" % (r(ofs/100), u(ofs%100))
with open("timezones.json", "w") as f:
    f.write(json.dumps(tt, sort_keys=True, indent=4, separators=(',', ': ')))
