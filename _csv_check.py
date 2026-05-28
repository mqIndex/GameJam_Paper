import csv, sys

rows = list(csv.reader(open(r'd:\godot_game\GameJam\GameJam_Paper\Project\data\cards.csv', encoding='utf-8')))
hdr = rows[0]
H = len(hdr)
print('HEADER LEN', H)

bool_cols = ['in_starter','in_shop','emotion_invert','reroll_event','event_preview',
             'discard_then_draw','topdeck_pick','shatter','mob_swing','shop_unique',
             'daily_exile','discard_hand_redraw']
num_cols  = ['cost','starter_count','buy_pct','sell_pct','price_pct','emotion_delta',
             'trade_price_pct','trade_shares','emotion_set','emotion_mul_turn',
             'emotion_mul_duration','discard_draw_count','liquidity_chance',
             'liquidity_reduction','mob_swing_mul','shop_price','daily_limit',
             'draw_count','share_cost','sell_bonus_mul','ap_bonus']

problems = []
for ridx, r in enumerate(rows[1:], start=2):
    if not r or not r[0] or r[0].startswith('#'):
        continue
    eid = r[0]
    if len(r) != H:
        problems.append((ridx, eid, 'len=%d (expect %d) extras=%r' % (len(r), H, r[H:] if len(r)>H else [])))
    d = dict(zip(hdr, r))
    for c in bool_cols:
        v = d.get(c, '').strip().upper()
        if v not in ('TRUE','FALSE','1','0','YES',''):
            problems.append((ridx, eid, '%s nonbool=%r' % (c, d.get(c))))
    for c in num_cols:
        v = d.get(c, '').strip()
        if v == '':
            continue
        try:
            float(v)
        except Exception:
            problems.append((ridx, eid, '%s nonnum=%r' % (c, d.get(c))))

if not problems:
    print('NO MISALIGNMENT DETECTED')
else:
    for p in problems:
        print(p)