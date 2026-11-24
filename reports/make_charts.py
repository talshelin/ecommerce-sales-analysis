"""make_charts.py
Draws the charts used in README.md and docs/decision_log.md.

The charts are drawn from the raw CSV files in data/raw/ with the same rules as the
SQL views in sql/03_clean_views.sql, so every number matches the SQL results:
  - sale = every status except canceled and unavailable
  - analysis window = January 2017 to August 2018
  - revenue = sum of item prices, without freight
  - late = delivered after the estimated date, compared as dates
  - one review per order: the newest one
  - a customer is a person (customer_unique_id)
Segment shares come from sql/07_rfm.sql.

Run from the repository root:  python reports/make_charts.py
Needs pandas and matplotlib.
"""
from pathlib import Path
import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
R = str(ROOT / 'data' / 'raw') + '/'
OUT = str(ROOT / 'reports' / 'images') + '/'

def load():
    """Orders with the flags of vw_orders: revenue, newest review, sale, window, valid delivery, late."""
    o = pd.read_csv(R+'olist_orders_dataset.csv', parse_dates=['order_purchase_timestamp','order_approved_at','order_delivered_carrier_date','order_delivered_customer_date','order_estimated_delivery_date'])
    c = pd.read_csv(R+'olist_customers_dataset.csv')
    it = pd.read_csv(R+'olist_order_items_dataset.csv')
    rv = pd.read_csv(R+'olist_order_reviews_dataset.csv', parse_dates=['review_creation_date','review_answer_timestamp'])
    o = o.merge(c[['customer_id','customer_unique_id','customer_state']], on='customer_id')
    rev = it.groupby('order_id').price.sum().rename('rev')
    o = o.merge(rev, left_on='order_id', right_index=True, how='left')
    rv = rv.sort_values(['review_creation_date','review_answer_timestamp'], ascending=False).drop_duplicates('order_id')
    o = o.merge(rv[['order_id','review_score']], on='order_id', how='left')
    o['month'] = o.order_purchase_timestamp.dt.to_period('M')
    o['is_sale'] = ~o.order_status.isin(['canceled','unavailable'])
    o['in_window'] = (o.order_purchase_timestamp>='2017-01-01')&(o.order_purchase_timestamp<'2018-09-01')
    o['valid'] = (o.order_status=='delivered')&o.order_delivered_customer_date.notna()
    dd = o.order_delivered_customer_date.dt.normalize(); ed = o.order_estimated_delivery_date.dt.normalize()
    o['days_late'] = (dd-ed).dt.days
    o['is_late'] = np.where(o.valid, (o.days_late>0).astype(float), np.nan)
    return o, it


import matplotlib; matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.ticker import FuncFormatter, PercentFormatter
BLUE='#1F77D0'; NAVY='#12239E'; GRAY='#A6A6A6'; RED='#D64550'; INK='#1B201D'; MUTED='#5B645E'
plt.rcParams.update({'font.family':'DejaVu Sans','font.size':10,'axes.edgecolor':'#CCCCCC','axes.labelcolor':MUTED,
  'xtick.color':MUTED,'ytick.color':MUTED,'axes.spines.top':False,'axes.spines.right':False,'figure.dpi':100})
def fig(n=1, w=11, h=4.2, title='', sub=''):
    f, ax = plt.subplots(1, n, figsize=(w,h))
    f.text(0.01, 0.97, title, fontsize=14, fontweight='bold', color=INK, va='top')
    if sub: f.text(0.01, 0.90, sub, fontsize=10, color=MUTED, va='top')
    return f, ax
def ptitle(ax, t): ax.set_title(t, loc='left', fontsize=11, color=INK, pad=8)
def save(f, name, top=0.78, left=0.07):
    f.subplots_adjust(top=top, left=left, right=0.98, bottom=0.14, wspace=0.28)
    f.savefig(OUT+name, dpi=160, facecolor='white'); plt.close(f); print('saved', name)
def grid(ax, axis='y'): ax.grid(axis=axis, color='#EEEEEE'); ax.set_axisbelow(True)

o,it = load()
s = o[o.is_sale & o.in_window]
months = pd.period_range('2017-01','2018-08',freq='M')
lab = [m.strftime('%b\n%Y') if m.month in (1,) or m==months[0] else m.strftime('%b') for m in months]

# ---------- README A: revenue by month + growth source
f, ax = fig(2, title='Revenue grew 7x in 20 months, driven by more orders, not bigger baskets',
            sub='Sale orders, January 2017 to August 2018. Revenue = item prices without freight (BRL).')
rev = s.groupby('month').rev.sum().reindex(months)
a = ax[0]; x = range(len(months))
a.plot(x, rev.values/1e3, color=BLUE, lw=2.4, marker='o', ms=3.5)
a.set_xticks(list(x)[::2]); a.set_xticklabels([lab[i] for i in x][::2], fontsize=8.5)
a.yaxis.set_major_formatter(FuncFormatter(lambda v,p: f'{v/1000:.1f}M' if v>=1000 else f'{v:.0f}K')); grid(a)
i = list(months).index(pd.Period('2017-11','M'))
a.annotate('Black Friday\n(Nov 2017)', (i, rev.iloc[i]/1e3), (i-6.5, rev.iloc[i]/1e3+20), fontsize=9, color=MUTED,
           arrowprops=dict(arrowstyle='-', color=GRAY))
a.annotate('120K', (0, rev.iloc[0]/1e3), (0.4, rev.iloc[0]/1e3-60), fontsize=9, color=INK)
a.annotate('849K', (19, rev.iloc[-1]/1e3), (17.2, rev.iloc[-1]/1e3-110), fontsize=9, color=INK)
a.set_ylim(0, 1100); ptitle(a, 'Monthly revenue (BRL)')
b = ax[1]
def jan_aug(y): d = s[(s.order_purchase_timestamp.dt.year==y)&(s.order_purchase_timestamp.dt.month<=8)]; return d
d17, d18 = jan_aug(2017), jan_aug(2018)
items = d18.rev.notna(); 
o17 = d17.rev.notna().sum(); o18 = d18.rev.notna().sum()
aov17 = d17.rev.sum()/o17; aov18 = d18.rev.sum()/o18
vals = [100*(d18.rev.sum()/d17.rev.sum()-1), 100*(o18/o17-1), 100*(aov18/aov17-1)]
bars = b.barh(['Revenue','Orders','Average order value'][::-1], vals[::-1], color=[GRAY, BLUE, NAVY])
for r,v in zip(bars, vals[::-1]): b.text(v+3, r.get_y()+r.get_height()/2, f'+{v:.1f}%', va='center', fontsize=10, color=INK)
b.set_xlim(0, 175); b.xaxis.set_major_formatter(FuncFormatter(lambda v,p: f'{v:.0f}%')); grid(b,'x')
ptitle(b, 'Jan-Aug 2018 vs Jan-Aug 2017')
print('growth', [round(v,1) for v in vals])
save(f, 'readme_a_growth.png')

# ---------- README B: monthly late rate + 1-star by delay
v = o[o.valid & o.in_window].copy()
def grp(r):
    if r.is_late==0: return 'On time'
    return '1-3 days\nlate' if r.days_late<=3 else ('4-7 days\nlate' if r.days_late<=7 else '8+ days\nlate')
v['g'] = v.apply(grp, axis=1)
f, ax = fig(2, title='1 in 15 orders arrives late, and late orders get far worse reviews',
            sub='Delivered orders with a delivery date, January 2017 to August 2018. Late = delivered after the estimated date.')
a = ax[0]; lr = v.groupby('month').is_late.mean().reindex(months)*100
a.plot(x, lr.values, color=RED, lw=2.4, marker='o', ms=3.5); a.axhline(6.8, color=GRAY, ls='--', lw=1)
a.text(19.3, 6.8+0.5, 'average 6.8%', fontsize=8.5, color=MUTED, ha='right')
a.set_xticks(list(x)[::2]); a.set_xticklabels([lab[i] for i in x][::2], fontsize=8.5)
a.yaxis.set_major_formatter(PercentFormatter(decimals=0)); a.set_ylim(0, 22); a.set_yticks([0,5,10,15,20]); grid(a)
for p in ['2017-11','2018-03']:
    i = list(months).index(pd.Period(p,'M')); a.text(i, lr.iloc[i]+0.8, f'{lr.iloc[i]:.0f}%', ha='center', fontsize=9, color=RED)
ptitle(a, 'Late deliveries by month')
b = ax[1]; r = v[v.review_score.notna()]
order = ['On time','1-3 days\nlate','4-7 days\nlate','8+ days\nlate']
one = r.groupby('g').review_score.apply(lambda q:(q==1).mean()*100).reindex(order)
bars = b.bar(order, one.values, color=[GRAY, RED, RED, RED], width=0.6)
for bb,val in zip(bars, one.values): b.text(bb.get_x()+bb.get_width()/2, val+1.5, f'{val:.1f}%', ha='center', fontsize=10, color=INK)
b.yaxis.set_major_formatter(PercentFormatter(decimals=0)); b.set_ylim(0, 80); grid(b)
ptitle(b, 'Share of 1-star reviews, by days late')
print('1star', one.round(1).to_dict())
save(f, 'readme_b_delivery.png')

# ---------- README C: retention curve + cumulative return
first = o[o.is_sale].groupby('customer_unique_id').order_purchase_timestamp.min().dt.to_period('M').rename('cohort')
coh = first[(first>=months[0])&(first<=months[-1])]
act = s[['customer_unique_id','month']].merge(coh, left_on='customer_unique_id', right_index=True).drop_duplicates()
act['k'] = (act.month-act.cohort).apply(lambda q:q.n)
cells = act.groupby(['cohort','k']).size().rename('act').reset_index(); cells['size']=cells.cohort.map(coh.value_counts())
ret = cells[cells.k>=1].groupby('k')[['act','size']].sum(); ret = 100*ret.act/ret['size']
so = o[o.is_sale].sort_values('order_purchase_timestamp')
so['prev'] = so.groupby('customer_unique_id').order_purchase_timestamp.shift()
gap = (so.order_purchase_timestamp.dt.normalize()-so.prev.dt.normalize()).dt.days; gap = gap[gap>0].sort_values()
f, ax = fig(2, title='Only about 5 in 1,000 new customers buy again the next month',
            sub='A customer is a person (customer_unique_id). Cohort = month of the first sale.')
a = ax[0]; a.plot(ret.index, ret.values, color=BLUE, lw=2.4, marker='o', ms=3.5)
a.yaxis.set_major_formatter(PercentFormatter(decimals=1)); a.set_ylim(0, 0.6); grid(a)
a.set_xlabel('Months since first order'); a.set_xticks(range(1,20,2))
a.text(1.3, ret.iloc[0]+0.02, f'{ret.iloc[0]:.2f}%', fontsize=9.5, color=INK)
ptitle(a, 'Average cohort retention (month 0 = 100%)')
b = ax[1]; cum = np.arange(1, len(gap)+1)/len(gap)*100
b.plot(gap.values, cum, color=BLUE, lw=2.4)
for d,lbl,yy in [(69,'50% within 69 days',50),(280,'90% within 280 days',90)]:
    b.axvline(d, color=GRAY, ls='--', lw=1); b.plot([d],[yy],'o',color=NAVY,ms=6); b.text(d+12, yy-7, lbl, fontsize=9.5, color=INK)
b.axvspan(280, 700, color=RED, alpha=0.06); b.text(470, 20, 'treated as lost\n(churn threshold)', fontsize=9, color=RED, ha='center')
b.set_xlim(0, 700); b.set_ylim(0, 102); b.yaxis.set_major_formatter(PercentFormatter(decimals=0)); grid(b)
b.set_xlabel('Days since the previous order')
ptitle(b, f'Days until the next order ({len(gap):,} repeat orders)')
print('ret', ret.round(2).head(4).to_dict(), 'gaps', len(gap), gap.median(), gap.quantile(.9))
save(f, 'readme_c_retention.png', top=0.76)

# ---------- README D: segments (numbers from sql/07_rfm.sql)
seg = pd.DataFrame({'segment':['Recent big spenders','Lost big spenders','Cooling down','Recent customers','Lost customers','Champions','Lost repeat customers'],
  'cust':[15.6,13.0,24.0,23.1,21.3,2.1,0.9],'rev':[29.3,25.7,22.0,9.0,8.4,3.9,1.7],
  'lost':[False,True,False,False,True,False,True]})[::-1]
f, ax = fig(1, w=11, h=4.6, title='Big spenders bring 55% of revenue, and almost half of that is already lost',
            sub='RFM segments, 94,707 customers. Lost = no order for 280+ days (red labels).')
a = ax; y = np.arange(len(seg)); hgt=0.38
a.barh(y+hgt/2, seg.cust, hgt, color=GRAY, label='Share of customers')
a.barh(y-hgt/2, seg.rev, hgt, color=NAVY, label='Share of revenue')
for yi,(cv,rv) in enumerate(zip(seg.cust, seg.rev)):
    a.text(cv+0.4, yi+hgt/2, f'{cv:.1f}%', va='center', fontsize=8.5, color=MUTED)
    a.text(rv+0.4, yi-hgt/2, f'{rv:.1f}%', va='center', fontsize=9, color=INK, fontweight='bold')
a.set_yticks(y); a.set_yticklabels(seg.segment)
for t,l in zip(a.get_yticklabels(), seg.lost): t.set_color(RED if l else INK)
a.xaxis.set_major_formatter(PercentFormatter(decimals=0)); a.set_xlim(0, 34); grid(a,'x')
a.legend(loc='lower right', frameon=False)
save(f, 'readme_d_segments.png', top=0.80, left=0.18)

# ---------- Decision log charts
allm = pd.period_range('2016-09','2018-10',freq='M')
cnt = o.groupby('month').size().reindex(allm, fill_value=0)
f, ax = fig(1, w=11, h=4.0, title='The first and last months are almost empty, so trends use January 2017 to August 2018',
            sub='All orders per month, any status. Gray = left out of trends (349 orders, 0.35%).')
cols = [BLUE if months[0]<=m<=months[-1] else GRAY for m in allm]
ax.bar(range(len(allm)), cnt.values, color=cols)
ax.set_xticks(range(len(allm))); ax.set_xticklabels([m.strftime('%b\n%y') for m in allm], fontsize=7.5)
for i,m in enumerate(allm):
    if not (months[0]<=m<=months[-1]): ax.text(i, cnt.iloc[i]+120, f'{cnt.iloc[i]}', ha='center', fontsize=8, color=MUTED)
i = list(allm).index(pd.Period('2017-11','M')); ax.text(i, cnt.iloc[i]+150, '7,544\nBlack Friday', ha='center', fontsize=8.5, color=INK)
ax.set_ylim(0, 8700); ax.yaxis.set_major_formatter(FuncFormatter(lambda v,p: f'{v:,.0f}')); grid(ax)
save(f, 'dl_orders_per_month.png', top=0.80)

rv = pd.read_csv(R+'olist_order_reviews_dataset.csv').review_score.value_counts(normalize=True).sort_index()*100
f, ax = fig(1, w=8, h=3.6, title='Unhappy customers give 1 star, not 2 or 3', sub='Share of reviews by score (99,224 reviews).')
bars = ax.bar([str(k) for k in rv.index], rv.values, color=[RED, GRAY, GRAY, GRAY, BLUE], width=0.6)
for bb,val in zip(bars, rv.values): ax.text(bb.get_x()+bb.get_width()/2, val+1.2, f'{val:.1f}%', ha='center', fontsize=10, color=INK)
ax.set_xlabel('Review score'); ax.yaxis.set_major_formatter(PercentFormatter(decimals=0)); ax.set_ylim(0, 68); grid(ax)
save(f, 'dl_review_scores.png', top=0.78)

f, ax = fig(1, w=8, h=3.4, title='Missing dates grow along the order journey', sub='Orders without each date (99,441 orders).')
miss = [o.order_approved_at.isna().sum(), o.order_delivered_carrier_date.isna().sum(), o.order_delivered_customer_date.isna().sum()]
names = ['Approved','Handed to carrier','Delivered']
bars = ax.bar(names, miss, color=[GRAY, GRAY, BLUE], width=0.55)
for bb,val in zip(bars, miss): ax.text(bb.get_x()+bb.get_width()/2, val+60, f'{val:,}', ha='center', fontsize=10, color=INK)
ax.set_ylim(0, 3400); grid(ax); ax.yaxis.set_major_formatter(FuncFormatter(lambda v,p: f'{v:,.0f}'))
print('missing', miss)
save(f, 'dl_missing_dates.png', top=0.76)

f, ax = fig(1, w=9, h=3.6, title='A few expensive items pull the average up, so the median is the typical price',
            sub='Item prices (112,650 items), log scale.')
ax.hist(it.price, bins=np.logspace(np.log10(0.85), np.log10(7000), 60), color=GRAY)
ax.yaxis.set_major_formatter(FuncFormatter(lambda v,p: f'{v:,.0f}')); ax.set_xscale('log'); med, avg = it.price.median(), it.price.mean()
for val,c,t in [(med,NAVY,'median'),(avg,RED,'average')]:
    ax.axvline(val, color=c, lw=2)
    ax.text(val*(0.93 if t=='median' else 1.07), ax.get_ylim()[1]*0.9, f'{t} {val:.0f} BRL', color=c, fontsize=9.5, ha='right' if t=='median' else 'left')
ax.xaxis.set_major_formatter(FuncFormatter(lambda v,p: f'{v:,.0f}')); ax.set_xlabel('Item price (BRL)'); grid(ax)
print('price', med, round(avg,1), it.price.max())
save(f, 'dl_price_distribution.png', top=0.78)

f, ax = fig(1, w=9, h=3.6, title='29% of repeat orders are a split shopping session, not a return',
            sub='3,217 repeat orders by days since the same customer\'s previous order.')
d = (so.order_purchase_timestamp.dt.normalize()-so.prev.dt.normalize()).dt.days.dropna()
vals = [(d==0).sum(), (d>0).sum()]
bars = ax.barh(['Later day', 'Same day'], vals[::-1], color=[BLUE, GRAY], height=0.5)
for bb,val in zip(bars, vals[::-1]): ax.text(val+30, bb.get_y()+bb.get_height()/2, f'{val:,} ({100*val/len(d):.0f}%)', va='center', fontsize=10, color=INK)
ax.set_xlim(0, 2900); grid(ax,'x'); ax.xaxis.set_major_formatter(FuncFormatter(lambda v,p: f'{v:,.0f}'))
save(f, 'dl_same_day_repeats.png', top=0.76, left=0.12)

c = o[o.is_sale].groupby('customer_unique_id').size().clip(upper=3).value_counts(normalize=True).sort_index()*100
f, ax = fig(1, w=8, h=3.4, title='97% of customers have one order, so frequency is used as 1 vs 2+',
            sub='People with at least one sale order (94,990), by number of orders.')
bars = ax.bar(['1 order','2 orders','3+ orders'], c.values, color=[GRAY, BLUE, BLUE], width=0.55)
for bb,val in zip(bars, c.values): ax.text(bb.get_x()+bb.get_width()/2, val+2, f'{val:.2f}%', ha='center', fontsize=10, color=INK)
ax.set_ylim(0, 112); ax.yaxis.set_major_formatter(PercentFormatter(decimals=0)); grid(ax)
save(f, 'dl_orders_per_customer.png', top=0.76)

# sellers scatter
ns = it.groupby('order_id').seller_id.nunique(); single = ns[ns==1].index
sel = it.drop_duplicates('order_id')[['order_id','seller_id']]
vv = o[o.valid & o.in_window & o.order_id.isin(single)].merge(sel, on='order_id')
g = vv.groupby('seller_id').agg(n=('is_late','size'), late=('is_late','sum')); g = g[g.n>=30]; g['pct']=100*g.late/g.n
bad = g.pct>=15; share = 100*g[bad].late.sum()/vv.is_late.sum()
f, ax = fig(1, w=10, h=4.2, title=f'Some sellers are often late, but they cause only {share:.0f}% of late deliveries',
            sub=f'{len(g)} sellers with 30+ deliveries (single-seller orders). Red = late 15% of the time or more ({bad.sum()} sellers).')
ax.scatter(g.n[~bad], g.pct[~bad], s=14, color=GRAY, alpha=0.7)
ax.scatter(g.n[bad], g.pct[bad], s=18, color=RED)
ax.axhline(15, color=RED, ls='--', lw=1); ax.set_xscale('log')
ax.set_xlabel('Deliveries (log scale)'); ax.set_ylabel('Late deliveries'); ax.yaxis.set_major_formatter(PercentFormatter(decimals=0)); grid(ax,'both')
ax.xaxis.set_major_formatter(FuncFormatter(lambda v,p: f'{v:,.0f}'))
print('sellers', len(g), bad.sum(), round(share,1))
save(f, 'dl_sellers.png', top=0.80)

f, ax = fig(1, w=9, h=3.6, title='Comparing with the time would mark 1,292 on-time orders as late',
            sub='Late rate of delivered orders. The estimated date has no time (00:00).')
dt_late = (o[o.valid].order_delivered_customer_date > o[o.valid].order_estimated_delivery_date).mean()*100
vals = [o[o.valid].is_late.mean()*100, dt_late]
bars = ax.barh(['Compared as dates (used)','Compared with the time'][::-1], vals[::-1], color=[GRAY, BLUE], height=0.5)
for bb,val in zip(bars, vals[::-1]): ax.text(val+0.1, bb.get_y()+bb.get_height()/2, f'{val:.1f}%', va='center', fontsize=10, color=INK)
ax.set_xlim(0, 10); ax.xaxis.set_major_formatter(PercentFormatter(decimals=0)); grid(ax,'x')
print('late dt', vals, (o[o.valid].order_delivered_customer_date > o[o.valid].order_estimated_delivery_date).sum()-o[o.valid].is_late.sum())
save(f, 'dl_late_definition.png', top=0.76, left=0.25)
