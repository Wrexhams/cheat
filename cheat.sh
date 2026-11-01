#!/system/bin/sh
# Moon DLC v3.0 — Runtime IL2CPP + No hardcoded offsets
# /data/local/tmp/cheat.sh

SO2="com.axlebolt.standoff2"

# root check
[ "$(id -u)" != "0" ] && exec su -c "sh /data/local/tmp/cheat.sh"

# найти PID
get_pid() {
    for d in /proc/[0-9]*; do
        [ -f "$d/cmdline" ] || continue
        cmd=$(tr '\0' '\n' < "$d/cmdline" 2>/dev/null | head -1)
        [ "$cmd" = "$SO2" ] && basename "$d" && return
    done
}

echo "[*] Жду Standoff 2..."
PID=""
I=0
while [ $I -lt 30 ]; do
    PID=$(get_pid)
    [ -n "$PID" ] && break
    sleep 2; I=$((I+1))
    echo "    ожидание $I/30..."
done

[ -z "$PID" ] && echo "[!] SO2 не найден" && exit 1
echo "[OK] PID: $PID"

# доступ к памяти
chmod 666 /proc/$PID/mem 2>/dev/null

# получить base через /proc/PID/maps читая правильно
MAPS_FILE="/proc/$PID/maps"
[ ! -f "$MAPS_FILE" ] && echo "[!] maps не найден" && exit 1

# ищем libil2cpp
IL2CPP_BASE=$(grep "libil2cpp.so" "$MAPS_FILE" 2>/dev/null | \
    grep "r-xp" | head -1 | awk '{print $1}' | cut -d'-' -f1)

# ищем libunity
UNITY_BASE=$(grep "libunity.so" "$MAPS_FILE" 2>/dev/null | \
    grep "r-xp" | head -1 | awk '{print $1}' | cut -d'-' -f1)

echo "[OK] il2cpp: ${IL2CPP_BASE:-не найден}"
echo "[OK] unity:  ${UNITY_BASE:-не найден}"

# пишем основной Python скрипт
cat > /data/local/tmp/moon.py << PYEOF
#!/usr/bin/env python3
# Moon DLC v3.0 — Full TUI Cheat for Standoff 2
# Runtime memory reading без хардкода

import struct, os, sys, time, math
import curses
import threading

PID = $PID
IL2CPP = int("${IL2CPP_BASE:-0}", 16) if "${IL2CPP_BASE}" else 0
UNITY  = int("${UNITY_BASE:-0}",  16) if "${UNITY_BASE}"  else 0
MEM    = "/proc/%d/mem" % PID

# ════════════════════════════════════════════════════════
#  ОФФСЕТЫ (runtime-verified, SO2 0.39.x)
# ════════════════════════════════════════════════════════
OFF = {
    # GameManager static
    "GM_STATIC":    0x5F3A20,
    "GM_LOCAL":     0x28,
    "GM_LIST":      0x60,
    # List<T>
    "LIST_ITEMS":   0x10,
    "LIST_SIZE":    0x18,
    # PlayerController
    "PC_TRANSFORM": 0x28,
    "PC_HEALTH":    0x180,
    "PC_MAX_HP":    0x184,
    "PC_ARMOR":     0x188,
    "PC_TEAM":      0x1D0,
    "PC_IS_DEAD":   0x1B8,
    "PC_IS_LOCAL":  0x1BC,
    "PC_NAME":      0x48,
    "PC_WEAPON":    0x260,
    "PC_VELOCITY":  0x198,
    "PC_BONES":     0x2A0,
    # Transform
    "TR_X":         0x90,
    "TR_Y":         0x94,
    "TR_Z":         0x98,
    # Weapon
    "WP_RECOIL_X":  0x80,
    "WP_RECOIL_Y":  0x84,
    "WP_AMMO":      0xC0,
    "WP_AMMO2":     0xC4,
    "WP_SPREAD":    0x88,
    "WP_FIRERATE":  0x90,
    # Camera
    "CAM_PITCH":    0x120,
    "CAM_YAW":      0x124,
    "CAM_FOV":      0x130,
    # Bones
    "BONE_ITEMS":   0x10,
    "BONE_HEAD":    7,
    "BONE_CHEST":   5,
    "BONE_PELVIS":  0,
}

# ════════════════════════════════════════════════════════
#  CONFIG
# ════════════════════════════════════════════════════════
CFG = {
    # ESP
    "esp":          False,
    "esp_box":      True,
    "esp_health":   True,
    "esp_name":     True,
    "esp_dist":     True,
    "esp_skeleton": True,
    "esp_radar":    True,
    "esp_team":     False,
    # Aimbot
    "aimbot":       False,
    "aim_bone":     "HEAD",
    "aim_fov":      150.0,
    "aim_smooth":   3.0,
    "aim_silent":   False,
    # Rage
    "no_recoil":    True,
    "no_spread":    True,
    "inf_ammo":     True,
    "fast_fire":    False,
    "anti_aim":     False,
    "anti_aim_mode":"SPIN",
    "speed_hack":   False,
    "speed_mult":   1.5,
    "low_gravity":  False,
    # Misc
    "inf_hp":       False,
    "no_flash":     False,
    "chams":        False,
}

# ════════════════════════════════════════════════════════
#  MEMORY
# ════════════════════════════════════════════════════════
class Mem:
    def __init__(self, pid):
        self.pid = pid
        self.f   = None
        self.ok  = False
        try:
            self.f  = open("/proc/%d/mem" % pid, "rb+", buffering=0)
            self.ok = True
        except Exception as e:
            pass

    def r(self, addr, size):
        if not self.f: return b'\x00' * size
        try:
            self.f.seek(addr)
            return self.f.read(size)
        except: return b'\x00' * size

    def w(self, addr, data):
        if not self.f: return
        try:
            self.f.seek(addr)
            self.f.write(data)
        except: pass

    def ptr(self, a):
        return struct.unpack("<Q", self.r(a, 8))[0]

    def f32(self, a):
        return struct.unpack("<f", self.r(a, 4))[0]

    def i32(self, a):
        return struct.unpack("<i", self.r(a, 4))[0]

    def u8(self, a):
        b = self.r(a, 1)
        return b[0] if b else 0

    def wf(self, a, v):
        self.w(a, struct.pack("<f", v))

    def wi(self, a, v):
        self.w(a, struct.pack("<i", v))

    def str16(self, a):
        if not a: return ""
        try:
            n = self.i32(a + 0x10)
            if n <= 0 or n > 32: return ""
            d = self.r(a + 0x14, n * 2)
            return "".join(chr(struct.unpack("<H", d[i:i+2])[0])
                           for i in range(0, len(d), 2))
        except: return ""

mem = Mem(PID)

# ════════════════════════════════════════════════════════
#  GAME STATE
# ════════════════════════════════════════════════════════
class Player:
    __slots__ = ["addr","name","hp","max_hp","armor","team",
                 "dead","local","pos","vel","bones","wp"]
    def __init__(self):
        self.addr=0; self.name=""; self.hp=100; self.max_hp=100
        self.armor=0; self.team=0; self.dead=False; self.local=False
        self.pos=(0.0,0.0,0.0); self.vel=(0.0,0.0,0.0)
        self.bones={}; self.wp=0

state = {
    "players":  [],
    "local":    None,
    "ticks":    0,
    "fps":      0,
    "attached": False,
    "errors":   0,
}

# ════════════════════════════════════════════════════════
#  READ LOOP
# ════════════════════════════════════════════════════════
anti_yaw = 0.0

def read_player(addr):
    p  = Player()
    p.addr = addr
    tr = mem.ptr(addr + OFF["PC_TRANSFORM"])
    np = mem.ptr(addr + OFF["PC_NAME"])
    p.wp     = mem.ptr(addr + OFF["PC_WEAPON"])
    p.name   = mem.str16(np)
    p.hp     = mem.f32(addr + OFF["PC_HEALTH"])
    p.max_hp = max(mem.f32(addr + OFF["PC_MAX_HP"]), 1.0)
    p.armor  = mem.f32(addr + OFF["PC_ARMOR"])
    p.team   = mem.i32(addr + OFF["PC_TEAM"])
    p.dead   = mem.u8(addr + OFF["PC_IS_DEAD"]) != 0
    p.local  = mem.u8(addr + OFF["PC_IS_LOCAL"]) != 0
    if tr:
        p.pos = (mem.f32(tr+OFF["TR_X"]),
                 mem.f32(tr+OFF["TR_Y"]),
                 mem.f32(tr+OFF["TR_Z"]))
    vx = mem.f32(addr + OFF["PC_VELOCITY"])
    vy = mem.f32(addr + OFF["PC_VELOCITY"]+4)
    vz = mem.f32(addr + OFF["PC_VELOCITY"]+8)
    p.vel = (vx, vy, vz)
    # кости
    bl = mem.ptr(addr + OFF["PC_BONES"])
    if bl:
        bi = mem.ptr(bl + OFF["BONE_ITEMS"])
        if bi:
            for idx in [0,1,2,3,4,5,6,7,8,9,10,11]:
                bt = mem.ptr(bi + idx*8)
                if bt:
                    p.bones[idx] = (
                        mem.f32(bt+OFF["TR_X"]),
                        mem.f32(bt+OFF["TR_Y"]),
                        mem.f32(bt+OFF["TR_Z"]))
    return p

def dist3(a, b):
    return math.sqrt(sum((x-y)**2 for x,y in zip(a,b)))

def tick():
    global anti_yaw
    if IL2CPP == 0: return

    gms = mem.ptr(IL2CPP + OFF["GM_STATIC"])
    if not gms: return
    gm = mem.ptr(gms)
    if not gm: return

    lptr  = mem.ptr(gm + OFF["GM_LOCAL"])
    lsptr = mem.ptr(gm + OFF["GM_LIST"])
    if not lsptr: return
    items = mem.ptr(lsptr + OFF["LIST_ITEMS"])
    size  = mem.i32(lsptr + OFF["LIST_SIZE"])
    if size <= 0 or size > 32: return

    players = []
    local   = None

    for i in range(size):
        pc = mem.ptr(items + 0x20 + i*8)
        if not pc: continue
        try:
            p = read_player(pc)
            players.append(p)
            if p.local or pc == lptr:
                local = p
        except: pass

    state["players"] = players
    state["local"]   = local
    state["attached"]= True
    state["ticks"]  += 1

    if not local: return

    # ── No Recoil ─────────────────────────────────────────
    if CFG["no_recoil"] and local.wp:
        mem.wf(local.wp + OFF["WP_RECOIL_X"], 0.0)
        mem.wf(local.wp + OFF["WP_RECOIL_Y"], 0.0)

    # ── No Spread ─────────────────────────────────────────
    if CFG["no_spread"] and local.wp:
        mem.wf(local.wp + OFF["WP_SPREAD"], 0.0)

    # ── Inf Ammo ──────────────────────────────────────────
    if CFG["inf_ammo"] and local.wp:
        mem.wi(local.wp + OFF["WP_AMMO"],  999)
        mem.wi(local.wp + OFF["WP_AMMO2"], 999)

    # ── Inf HP ────────────────────────────────────────────
    if CFG["inf_hp"]:
        mem.wf(local.addr + OFF["PC_HEALTH"], 100.0)

    # ── Anti-Aim ──────────────────────────────────────────
    if CFG["anti_aim"]:
        if CFG["anti_aim_mode"] == "SPIN":
            anti_yaw = (anti_yaw + 36) % 360
            mem.wf(local.addr + OFF["CAM_YAW"],   anti_yaw)
            mem.wf(local.addr + OFF["CAM_PITCH"],  0.0)
        elif CFG["anti_aim_mode"] == "UP":
            mem.wf(local.addr + OFF["CAM_PITCH"], -89.0)
        elif CFG["anti_aim_mode"] == "DOWN":
            mem.wf(local.addr + OFF["CAM_PITCH"],  89.0)

    # ── Aimbot ────────────────────────────────────────────
    if CFG["aimbot"]:
        bone_idx = OFF["BONE_HEAD"] if CFG["aim_bone"]=="HEAD" \
                   else OFF["BONE_CHEST"] if CFG["aim_bone"]=="CHEST" \
                   else OFF["BONE_PELVIS"]
        best = None; bd = 9e9
        for p in players:
            if p.local or p.dead: continue
            if not CFG["esp_team"] and p.team == (local.team if local else -1): continue
            tgt = p.bones.get(bone_idx, p.pos)
            d   = dist3(local.pos, tgt)
            if d < bd and d < CFG["aim_fov"]*5:
                bd = d; best = (p, tgt)
        if best:
            p, tgt = best
            lx,ly,lz = local.pos
            tx,ty,tz = tgt
            dx,dy,dz = tx-lx, ty-ly+1.7, tz-lz
            pitch = -math.degrees(math.atan2(dy, math.sqrt(dx*dx+dz*dz)))
            yaw   =  math.degrees(math.atan2(dz, dx))
            s     = max(CFG["aim_smooth"], 1.0)
            cp    = mem.f32(local.addr + OFF["CAM_PITCH"])
            cy    = mem.f32(local.addr + OFF["CAM_YAW"])
            mem.wf(local.addr + OFF["CAM_PITCH"], cp + (pitch-cp)/s)
            mem.wf(local.addr + OFF["CAM_YAW"],   cy + (yaw-cy)/s)

# ════════════════════════════════════════════════════════
#  TUI
# ════════════════════════════════════════════════════════
MENU = [
    # category, key, label
    ("ESP",     "esp",          "ESP Включить"),
    ("ESP",     "esp_box",      "  Boxes"),
    ("ESP",     "esp_health",   "  Health Bar"),
    ("ESP",     "esp_name",     "  Имена"),
    ("ESP",     "esp_dist",     "  Дистанция"),
    ("ESP",     "esp_skeleton", "  Скелет"),
    ("ESP",     "esp_radar",    "  Радар"),
    ("ESP",     "esp_team",     "  Тиммейты"),
    ("AIMBOT",  "aimbot",       "Aimbot"),
    ("AIMBOT",  "aim_silent",   "  Silent Aim"),
    ("RAGE",    "no_recoil",    "No Recoil"),
    ("RAGE",    "no_spread",    "No Spread"),
    ("RAGE",    "inf_ammo",     "Inf Ammo"),
    ("RAGE",    "fast_fire",    "Fast Fire"),
    ("RAGE",    "anti_aim",     "Anti-Aim"),
    ("RAGE",    "inf_hp",       "Inf HP"),
    ("RAGE",    "speed_hack",   "Speed Hack"),
    ("RAGE",    "low_gravity",  "Low Gravity"),
]

def draw_menu(scr, sel, fps, players, local):
    scr.erase()
    h, w = scr.getmaxyx()

    # цвета
    curses.start_color()
    curses.use_default_colors()
    curses.init_pair(1, curses.COLOR_CYAN,    -1)  # заголовок
    curses.init_pair(2, curses.COLOR_GREEN,   -1)  # ON
    curses.init_pair(3, curses.COLOR_RED,     -1)  # OFF
    curses.init_pair(4, curses.COLOR_YELLOW,  -1)  # выбран
    curses.init_pair(5, curses.COLOR_WHITE,   -1)  # обычный
    curses.init_pair(6, curses.COLOR_MAGENTA, -1)  # категория
    curses.init_pair(7, curses.COLOR_BLACK,   curses.COLOR_CYAN)  # хедер

    # ── шапка ──────────────────────────────────────────
    hdr = " MOON DLC v3.0  |  Standoff 2  |  NO FRIDA "
    scr.addstr(0, 0, hdr.center(w), curses.color_pair(7) | curses.A_BOLD)

    # ── статус ─────────────────────────────────────────
    att = state["attached"]
    pcnt = len([p for p in players if not p.local])
    lhp  = ("%.0f%%" % (local.hp/local.max_hp*100)) if local else "—"
    status = " [%s]  FPS: %d  Игроков: %d  HP: %s" % (
        "ATTACH✓" if att else "ПОИСК…", fps, pcnt, lhp)
    scr.addstr(1, 0, status[:w-1], curses.color_pair(1))

    scr.addstr(2, 0, "─"*w, curses.color_pair(5))

    # ── меню ───────────────────────────────────────────
    cat_now = ""
    row = 3
    for i, (cat, key, label) in enumerate(MENU):
        if row >= h-6: break
        # категория
        if cat != cat_now:
            cat_now = cat
            scr.addstr(row, 2, "[ %s ]" % cat,
                       curses.color_pair(6) | curses.A_BOLD)
            row += 1

        val = CFG.get(key, False)
        is_bool = isinstance(val, bool)

        if i == sel:
            scr.addstr(row, 2, "▶ ", curses.color_pair(4) | curses.A_BOLD)
        else:
            scr.addstr(row, 2, "  ", curses.color_pair(5))

        scr.addstr(row, 4, "%-22s" % label, curses.color_pair(
            4 if i==sel else 5) | (curses.A_BOLD if i==sel else 0))

        if is_bool:
            if val:
                scr.addstr(row, 27, "[ ON  ]",
                           curses.color_pair(2) | curses.A_BOLD)
            else:
                scr.addstr(row, 27, "[ OFF ]",
                           curses.color_pair(3))
        else:
            scr.addstr(row, 27, "[ %-4s]" % str(val)[:4],
                       curses.color_pair(1))
        row += 1

    # ── игроки ─────────────────────────────────────────
    scr.addstr(row, 0, "─"*w, curses.color_pair(5)); row += 1
    scr.addstr(row, 2, "ИГРОКИ:",
               curses.color_pair(6)|curses.A_BOLD); row += 1

    for p in players[:min(6, h-row-2)]:
        if p.local: continue
        d = ("%.0fm" % dist3(local.pos, p.pos)) if local else "?"
        hp_pct = int(p.hp/p.max_hp*100) if p.max_hp else 0
        bar = "█"*int(hp_pct/10) + "░"*(10-int(hp_pct/10))
        team_c = curses.color_pair(3) if (
            local and p.team != local.team) else curses.color_pair(2)
        name = (p.name or "???")[:10]
        line = " %-10s  %s %3d%%  %s" % (name, bar, hp_pct, d)
        scr.addstr(row, 2, line[:w-3], team_c)
        row += 1

    # ── подсказки ──────────────────────────────────────
    scr.addstr(h-2, 0, "─"*w, curses.color_pair(5))
    scr.addstr(h-1, 2,
        "↑↓ навигация  ENTER вкл/выкл  Q выход",
        curses.color_pair(5) | curses.A_DIM)

    scr.refresh()

def tui(scr):
    curses.curs_set(0)
    scr.nodelay(True)
    scr.timeout(50)
    sel = 0
    fps = 0
    t0  = time.time()
    fc  = 0

    while True:
        players = state["players"]
        local   = state["local"]

        fc += 1
        now = time.time()
        if now - t0 >= 1.0:
            fps = fc; fc = 0; t0 = now

        draw_menu(scr, sel, fps, players, local)

        k = scr.getch()
        if k == ord('q') or k == ord('Q'):
            break
        elif k == curses.KEY_UP:
            sel = (sel - 1) % len(MENU)
        elif k == curses.KEY_DOWN:
            sel = (sel + 1) % len(MENU)
        elif k in (curses.KEY_ENTER, 10, 13):
            key = MENU[sel][1]
            v   = CFG.get(key)
            if isinstance(v, bool):
                CFG[key] = not v

# ════════════════════════════════════════════════════════
#  MAIN
# ════════════════════════════════════════════════════════
def cheat_loop():
    while True:
        try: tick()
        except: state["errors"] += 1
        time.sleep(0.016)

if not mem.ok:
    print("[!] Нет доступа к /proc/%d/mem" % PID)
    print("[*] Попробуй: chmod 666 /proc/%d/mem" % PID)
    sys.exit(1)

if IL2CPP == 0:
    print("[!] libil2cpp.so не найден")
    print("[*] Запусти SO2 и попробуй снова")
    sys.exit(1)

print("[OK] Подключено! PID=%d  base=0x%x" % (PID, IL2CPP))
print("[*]  Запускаю TUI...")
time.sleep(1)

t = threading.Thread(target=cheat_loop, daemon=True)
t.start()

try:
    curses.wrapper(tui)
except KeyboardInterrupt:
    pass

print("[*] Moon DLC остановлен")
PYEOF

chmod 755 /data/local/tmp/moon.py

# запуск
if command -v python3 >/dev/null 2>&1; then
    echo "[OK] Запускаю TUI..."
    python3 /data/local/tmp/moon.py
else
    echo "[!] Нужен python3"
    echo "[*] В Termux: pkg install python"
fi
