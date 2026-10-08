#!/usr/bin/env python3
"""
Regenerates the charts in doc/PERFORMANCE.md's "Other apps" section:
doc/performance-throughput-fresh.svg, doc/performance-throughput.svg and
doc/performance-memory.svg. Plain Python 3, no dependencies. Usage:

    tools/perfcharts.py

The figures below are copied by hand from the balance report and throughput
tables in doc/PERFORMANCE.md; update them there first, then here, then rerun.
Values are per journal size: 1k, 10k, 100k, 1M transactions. None means no
result (the run was killed or not attempted); lb(v) means "at least v", drawn
with an open marker (used where a 1k time was under the 0.01s resolution).
"""
import math, os

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
out = lambda name: os.path.join(REPO, 'doc', name)

# One hue per family of apps; older versions are drawn lighter,
# repl sessions and cached runs are drawn dashed.
hue = {"hledger":"#d4b000", "ledger":"#1f8a36", "beancount":"#2f6fd0", "rust":"#d9700f", "tackler":"#c92a2a"}
style = {  # name: (family, shade 1.0 = full, dashed)
 "rustledger 0.24.0 (cached)":    ("rust",1.0,True),
 "rustledger 0.24.0 (first run)": ("rust",1.0,False),
 "Tackler 26.10.1":               ("tackler",1.0,False),
 "hledger 1.99.5 (repl)":           ("hledger",1.0,True),
 "hledger 1.99.5":                  ("hledger",1.0,False),
 "hledger 1.52":                  ("hledger",0.55,False),
 "Ledger 3.4.1 (repl)":           ("ledger",1.0,True),
 "Ledger 3.4.1":                  ("ledger",1.0,False),
 "Beancount 3.2.3 (cached)":      ("beancount",1.0,True),
 "Beancount 3.2.3 (first run)":   ("beancount",1.0,False),
 "Beancount 2.3.6 (cached)":      ("beancount",0.55,True),
 "Beancount 2.3.6 (first run)":   ("beancount",0.55,False),
}
lb = lambda v: ('lb', v)

# Transactions per second, from the flat balance report times. Legend order.
throughput = [
 ("rustledger 0.24.0 (cached)",    [lb(100e3),333e3,769e3,920e3]),
 ("rustledger 0.24.0 (first run)", [100e3,125e3,164e3,145e3]),
 ("Tackler 26.10.1",               [lb(100e3),500e3,910e3,1.15e6]),
 ("hledger 1.99.5 (repl)",           [77e3,150e3,310e3,380e3]),
 ("hledger 1.99.5",                  [20e3,53e3,71e3,72e3]),
 ("hledger 1.52",                  [12e3,22e3,25e3,25e3]),
 ("Ledger 3.4.1 (repl)",           [50e3,77e3,6.3e3,None]),
 ("Ledger 3.4.1",                  [33e3,56e3,6.7e3,None]),
 ("Beancount 2.3.6 (cached)",      [8.3e3,26e3,31e3,31e3]),
 ("Beancount 2.3.6 (first run)",   [8.3e3,25e3,18e3,16e3]),
 ("Beancount 3.2.3 (cached)",      [8.3e3,22e3,25e3,25e3]),
 ("Beancount 3.2.3 (first run)",   [8.3e3,22e3,15e3,14e3]),
]
# Peak memory (RSS) in MB for the flat balance report, fresh uncached runs. Legend order.
memory = [
 ("Tackler 26.10.1",               [7,24,139,1100]),
 ("Ledger 3.4.1",                  [15,53,405,None]),
 ("rustledger 0.24.0 (first run)", [14,72,574,5000]),
 ("Beancount 2.3.6 (first run)",   [36,68,748,8500]),
 ("Beancount 3.2.3 (first run)",   [42,74,756,8500]),
 ("hledger 1.99.5",                  [57,101,573,5200]),
 ("hledger 1.52",                  [56,128,868,8000]),
]

W,H = 760,430          # chart size
L,R,T,B = 70,250,40,50 # margins: left, right (legend), top, bottom
SIZES = [1e3,1e4,1e5,1e6]
SIZELABELS = ["1k","10k","100k","1M"]
FONT = "-apple-system, Segoe UI, Helvetica, Arial, sans-serif"

def mix(hexc, f):
    "Lighten a hex colour toward white; f=1 keeps it, smaller f lightens."
    r,g,b = [int(hexc[i:i+2],16) for i in (1,3,5)]
    return "#%02x%02x%02x" % tuple(int(c+(255-c)*(1-f)) for c in (r,g,b))

def label(name): return name.replace(' (first run)','')

def frame(title, ylabel, ymin, ymax, yticks, xlabel):
    "The common parts of a chart: background, title, grid, axes. Returns (svg lines, Y scale)."
    Y = lambda v: T+(1-(math.log10(v)-math.log10(ymin))/(math.log10(ymax)-math.log10(ymin)))*(H-T-B)
    o = [f"<svg xmlns='http://www.w3.org/2000/svg' width='{W}' height='{H}' viewBox='0 0 {W} {H}' font-family='{FONT}' font-size='12'>",
         f"<rect width='{W}' height='{H}' fill='white' rx='4'/>",
         f"<text x='{L}' y='22' font-size='14' font-weight='bold' fill='#222'>{title}</text>"]
    for v,lab in yticks:
        y = Y(v); o.append(f"<line x1='{L}' x2='{W-R}' y1='{y:.1f}' y2='{y:.1f}' stroke='#e6e6e6'/>")
        o.append(f"<text x='{L-6}' y='{y+4:.1f}' text-anchor='end' fill='#555'>{lab}</text>")
    o.append(f"<text x='{(L+W-R)/2:.0f}' y='{H-10}' text-anchor='middle' fill='#555'>{xlabel}</text>")
    o.append(f"<text transform='translate(14,{(T+H-B)/2:.0f}) rotate(-90)' text-anchor='middle' fill='#555'>{ylabel}</text>")
    return o, Y

def legend(o, rows, notes, swatch):
    for i,(name,_) in enumerate(rows):
        fam,sh,dashed = style[name]; c = mix(hue[fam],sh); ly = T+14+i*22; lx = W-R+20
        swatch(o, lx, ly, c, dashed)
        o.append(f"<text x='{lx+36}' y='{ly+4}' fill='#222'>{label(name)}</text>")
    for k,t in enumerate(notes):
        o.append(f"<text x='{W-R+20}' y='{T+14+len(rows)*22+8+16*k}' fill='#555' font-size='11'>{t}</text>")

def linechart(path, title, rows, ymin, ymax, ylabel, yticks, notes):
    "A log-log line chart, one line per row."
    o,Y = frame(title, ylabel, ymin, ymax, yticks, "transactions in journal (log scale)")
    X = lambda v: L+(math.log10(v)-3)/3*(W-L-R)
    for v,lab in zip(SIZES,SIZELABELS):
        x = X(v); o.append(f"<line x1='{x:.1f}' x2='{x:.1f}' y1='{T}' y2='{H-B}' stroke='#e6e6e6'/>")
        o.append(f"<text x='{x:.1f}' y='{H-B+18}' text-anchor='middle' fill='#555'>{lab}</text>")
    o.append(f"<rect x='{L}' y='{T}' width='{W-L-R}' height='{H-T-B}' fill='none' stroke='#999'/>")
    for name,vals in rows:
        fam,sh,dashed = style[name]; c = mix(hue[fam],sh); dash = "stroke-dasharray='7,5'" if dashed else ""
        pts = [(X(x), Y(v[1] if isinstance(v,tuple) else v), isinstance(v,tuple)) for x,v in zip(SIZES,vals) if v is not None]
        d = " ".join(f"{'M' if k==0 else 'L'}{x:.1f},{y:.1f}" for k,(x,y,_) in enumerate(pts))
        o.append(f"<path d='{d}' fill='none' stroke='{c}' stroke-width='2.2' {dash}/>")
        for x,y,islb in pts:
            o.append(f"<circle cx='{x:.1f}' cy='{y:.1f}' r='4' fill='{'white' if islb else c}' stroke='{c}' stroke-width='2.2'/>")
    def swatch(o, lx, ly, c, dashed):
        dash = "stroke-dasharray='7,5'" if dashed else ""
        o.append(f"<line x1='{lx}' x2='{lx+28}' y1='{ly}' y2='{ly}' stroke='{c}' stroke-width='2.2' {dash}/>")
        o.append(f"<circle cx='{lx+14}' cy='{ly}' r='4' fill='{c}' stroke='{c}'/>")
    legend(o, rows, notes, swatch)
    o.append("</svg>"); open(path,'w').write("\n".join(o))

def barchart(path, title, rows, ymin, ymax, ylabel, yticks, notes):
    "A grouped bar chart with a log y axis: one group per journal size, one bar per row."
    o,Y = frame(title, ylabel, ymin, ymax, yticks, "transactions in journal")
    gw = (W-L-R)/len(SIZES); bw = gw*0.8/len(rows)
    for g,lab in enumerate(SIZELABELS):
        gx = L+g*gw
        o.append(f"<text x='{gx+gw/2:.1f}' y='{H-B+18}' text-anchor='middle' fill='#555'>{lab}</text>")
        for i,(name,vals) in enumerate(rows):
            v = vals[g]
            if v is None: continue
            fam,sh,_ = style[name]; c = mix(hue[fam],sh); x = gx+gw*0.1+i*bw; y = Y(v)
            o.append(f"<rect x='{x:.1f}' y='{y:.1f}' width='{bw-1.5:.1f}' height='{H-B-y:.1f}' fill='{c}'/>")
    o.append(f"<rect x='{L}' y='{T}' width='{W-L-R}' height='{H-T-B}' fill='none' stroke='#999'/>")
    legend(o, rows, notes, lambda o,lx,ly,c,_: o.append(f"<rect x='{lx}' y='{ly-7}' width='28' height='14' fill='{c}'/>"))
    o.append("</svg>"); open(path,'w').write("\n".join(o))

tps_ticks = [(v, f"{int(v)//1000}k" if v<1e6 else "1M") for v in [10e3,20e3,50e3,100e3,200e3,500e3,1e6]]
mem_ticks = [(v, f"{v} MB" if v<1000 else f"{v//1000} GB") for v in [10,20,50,100,200,500,1000,2000,5000,10000]]
fresh = [r for r in throughput if '(cached)' not in r[0] and '(repl)' not in r[0]]

linechart(out('performance-throughput-fresh.svg'), "Flat balance report throughput, uncached (transactions per second)",
          fresh, 4e3, 1.5e6, "transactions per second (log scale)", tps_ticks, [])
linechart(out('performance-throughput.svg'), "Flat balance report throughput, including cached/repl (transactions per second)",
          throughput, 4e3, 1.5e6, "transactions per second (log scale)", tps_ticks, ["dashed: repl session or cached run"])
barchart(out('performance-memory.svg'), "Flat balance report peak memory (lower is better)",
         memory, 5, 12000, "peak memory, MB (log scale)", mem_ticks, ["fresh uncached runs"])
