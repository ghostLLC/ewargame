#!/usr/bin/env python3
"""Generate and validate EWarGame scenario content (stdlib only).

Addresses content-review 2026-09-10:
- Explicit unit type/size (no name-based HQ inference)
- Scenario-specific rosters and maps
- Legal deployment (no impassable water spawns)
- Distinctive geography, labels, and objectives
- Tutorial with combat roster and separated staging
"""
from __future__ import annotations

import argparse
import json
import re
from collections import deque
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "game" / "data" / "scenarios"

TERRAINS = {
    "plains", "forest", "hills", "mountain", "desert",
    "marsh", "town", "city", "bocage", "water",
}
TYPES = {
    "infantry", "armor", "mechanized", "motorized", "recon",
    "artillery", "engineer", "airborne", "hq", "logistics", "air_defense",
}
ERA = {
    "ww2": {
        "recon_range": 2, "command_range": 4, "supply_range": 12,
        "air_power": 0.7, "air_defense": 0.3, "antitank": 0.25,
        "command_delay": 1, "supply_efficiency": 0.85,
    },
    "coldwar": {
        "recon_range": 3, "command_range": 6, "supply_range": 16,
        "air_power": 1.0, "air_defense": 0.65, "antitank": 0.55,
        "command_delay": 0, "supply_efficiency": 1.0,
    },
    "modern": {
        "recon_range": 4, "command_range": 8, "supply_range": 20,
        "air_power": 1.25, "air_defense": 0.9, "antitank": 0.8,
        "command_delay": 0, "supply_efficiency": 1.15,
    },
}

SOURCES = {
    "normandy_utm": [
        {
            "title": "U.S. Army CMH: Utah Beach to Cherbourg",
            "url": "https://history.army.mil/Publications/Publications-Catalog/Utah-Beach-to-Cherbourg/",
            "note": "VII Corps from Utah Beach to Cherbourg; used for June 6 bridgehead formations and beach-exit problem.",
        },
        {
            "title": "U.S. Army CMH: Cross-Channel Attack",
            "url": "https://history.army.mil/Publications/Publications-Catalog/Cross-Channel-Attack/",
            "note": "First Army operations through 1 July 1944; campaign context for the beachhead.",
        },
    ],
    "normandy_cobra": [
        {
            "title": "U.S. Army CMH: Breakout and Pursuit",
            "url": "https://history.army.mil/portals/143/Images/Publications/catalog/7-5.pdf",
            "note": "COBRA, Saint-Lô and breakout; used for late-July VII Corps / armor formations only.",
        },
    ],
    "sinai": [
        {
            "title": "IDF: What Was the 1973 Yom Kippur War?",
            "url": "https://www.idf.il/en/mini-sites/wars-and-operations/what-was-the-1973-yom-kippur-war/",
            "note": "Sinai front, canal fortifications and counterattack context.",
        },
        {
            "title": "U.S. Army CMH: On Operational Art",
            "url": "https://history.army.mil/Portals/143/Images/Publications/Publication%20By%20Title%20Images/O%20titles%20PDF/cmhPub_70-54.pdf",
            "note": "Operational tempo and logistics background for 1973.",
        },
    ],
    "golan": [
        {
            "title": "IDF: What Was the 1973 Yom Kippur War?",
            "url": "https://www.idf.il/en/mini-sites/wars-and-operations/what-was-the-1973-yom-kippur-war/",
            "note": "Golan highland defense; northern front formations used here, not Sinai corps.",
        },
        {
            "title": "IDF: Lt. Gen. David Elazar",
            "url": "https://www.idf.il/en/mini-sites/past-chiefs-of-staff/lt-gen-david-elazar-1972-1974/",
            "note": "Reserve call-up and Golan decisions.",
        },
    ],
    "gulf": [
        {
            "title": "U.S. Army CMH: Jayhawk! The VII Corps in the Persian Gulf War",
            "url": "https://history.army.mil/Publications/Publications-Catalog/Jayhawk/",
            "note": "VII Corps deep maneuver (left hook) formation context.",
        },
        {
            "title": "U.S. Army CMH: War in the Persian Gulf",
            "url": "https://history.army.mil/Publications/Publications-Catalog/War-in-the-Persian-Gulf-ODS-and-DS/",
            "note": "Desert Storm ground campaign overview.",
        },
    ],
    "kuwait": [
        {
            "title": "U.S. Army CMH: War in the Persian Gulf",
            "url": "https://history.army.mil/Publications/Publications-Catalog/War-in-the-Persian-Gulf-ODS-and-DS/",
            "note": "Kuwait theater liberation and coastal axis.",
        },
        {
            "title": "U.S. Army CMH: Army History No. 118",
            "url": "https://history.army.mil/Portals/143/Images/Publications/ArmyHistoryMag/pdf/AH118.pdf",
            "note": "Left hook, coastal feint and corps-level task organization.",
        },
    ],
    "tutorial": [],
}

DESIGN_NOTE = (
    "这是受真实战役地理与编制启发的可玩作战级抽象。"
    "编制名称与战线归属来自公开史料筛选；六角地图、单位位置、战斗数值、补给、"
    "时间尺度与胜利条件均为游戏设计，不代表精确历史地图、兵力或战果。"
)


def slug(s: str) -> str:
    return re.sub(r"[^a-z0-9]+", "_", s.lower()).strip("_")


def tile(q: int, r: int, terrain: str = "plains", **kw) -> dict:
    elev = 2 if terrain == "mountain" else 1 if terrain in ("hills", "city") else 0
    row = {
        "q": q, "r": r, "terrain": terrain, "elevation": elev,
        "road": False, "rail": False, "river": False, "bridge": False, "label": "",
    }
    row.update(kw)
    if row["bridge"]:
        row["river"] = True
    return row


def formation(
    name: str,
    type_: str,
    size: str,
    side: int,
    q: int,
    r: int,
    *,
    strength: float = 88.0,
    organization: float = 82.0,
    quality: float = 1.0,
    fuel: float | None = None,
    ammo: float | None = None,
    fatigue: float = 0.0,
    idx: int = 0,
) -> dict:
    motor = type_ in ("armor", "mechanized", "motorized", "recon", "hq", "logistics", "air_defense")
    return {
        "id": f"s{side}_{idx:02d}_{slug(name)[:40]}",
        "name": name,
        "side": side,
        "q": q,
        "r": r,
        "type": type_,
        "size": size,
        "formation": name,
        "strength": float(strength),
        "organization": float(organization),
        "fatigue": float(fatigue),
        "fuel": 95.0 if motor else 80.0 if fuel is None else float(fuel),
        "ammo": 88.0 if ammo is None else float(ammo),
        "quality": float(quality),
    }


def place_list(rows: list[tuple], side: int, start_idx: int = 1) -> list[dict]:
    """rows: (name, type, size, q, r, optional strength, org, quality)."""
    out = []
    for i, row in enumerate(rows):
        name, type_, size, q, r = row[:5]
        extra = row[5:]
        kwargs = {}
        if len(extra) >= 1:
            kwargs["strength"] = extra[0]
        if len(extra) >= 2:
            kwargs["organization"] = extra[1]
        if len(extra) >= 3:
            kwargs["quality"] = extra[2]
        out.append(formation(name, type_, size, side, q, r, idx=start_idx + i, **kwargs))
    return out


def scenario_shell(
    sid: str,
    title: str,
    subtitle: str,
    era: str,
    date: str,
    width: int,
    height: int,
    hex_km: int,
    turn_hours: int,
    max_turns: int,
    seed: int,
    description: str,
    side0: str,
    color0: str,
    side1: str,
    color1: str,
    tiles: list[dict],
    units: list[dict],
    objectives: list[dict],
    depots: list[dict],
    sources_key: str,
    design_notes: str = DESIGN_NOTE,
    reinforcements: list | None = None,
    extra: dict | None = None,
) -> dict:
    data = {
        "id": sid,
        "title": title,
        "subtitle": subtitle,
        "era": era,
        "date": date,
        "description": description,
        "width": width,
        "height": height,
        "hex_km": hex_km,
        "turn_hours": turn_hours,
        "max_turns": max_turns,
        "seed": seed,
        "sides": [
            {"name": side0, "color": color0},
            {"name": side1, "color": color1},
        ],
        "tiles": tiles,
        "units": units,
        "objectives": objectives,
        "depots": depots,
        "reinforcements": reinforcements or [],
        "era_rules": dict(ERA[era]),
        "sources": SOURCES.get(sources_key, []),
        "design_notes": design_notes,
    }
    if extra:
        data.update(extra)
    return data


# ---------------------------------------------------------------------------
# Maps
# ---------------------------------------------------------------------------

def map_tutorial(w: int = 14, h: int = 10) -> list[dict]:
    tiles = []
    for r in range(h):
        for q in range(w):
            t = "plains"
            if q in (6, 7) and 2 <= r <= 7:
                t = "water"
            if (q, r) in {(3, 2), (10, 2), (3, 7), (10, 7)}:
                t = "hills"
            if (q, r) in {(5, 4), (8, 5)}:
                t = "town"
            row = tile(q, r, t)
            if q in (6, 7) and r in (4, 5):
                row["terrain"] = "water"
                row["bridge"] = True
                row["river"] = True
            if r == 4 or q == 3 or q == 10:
                row["road"] = True
            label = {
                (2, 4): "蓝方出发阵地",
                (11, 4): "红方出发阵地",
                (5, 4): "河谷集镇",
                (8, 5): "东岸要点",
                (6, 4): "中央桥",
                (7, 5): "南侧桥",
            }.get((q, r), "")
            row["label"] = label
            tiles.append(row)
    return tiles


def map_normandy_bridgehead(w: int = 28, h: int = 18) -> list[dict]:
    """Utah-style: sea west, beach exits, Cotentin marshes, inland towns."""
    tiles = []
    for r in range(h):
        for q in range(w):
            t = "plains"
            if q <= 2:
                t = "water"
            elif q == 3:
                t = "plains"
            elif 5 <= q <= 8 and r in range(3, 15) and (r + q) % 3 != 0:
                t = "marsh"
            elif 9 <= q <= 16 and (q * 2 + r) % 5 < 2:
                t = "bocage"
            elif q >= 22 and (q + r) % 4 == 0:
                t = "forest"
            elif (q + r) % 11 == 0:
                t = "hills"
            row = tile(q, r, t)
            # Causeways / beach exits
            if q == 4 and r in (5, 9, 13):
                row["road"] = True
                row["terrain"] = "plains"
            if r in (5, 9, 13) or q in (4, 12, 18, 24):
                row["road"] = True
            if q == 10 and r in (8, 9):
                row["river"] = True
                row["terrain"] = "water"
                row["bridge"] = r == 9
            label = {
                (3, 5): "犹他滩头",
                (3, 13): "滩头南翼",
                (7, 5): "Causeway 1",
                (7, 9): "Causeway 2",
                (7, 13): "Causeway 3",
                (12, 4): "圣梅尔埃格利斯",
                (12, 12): "卡朗唐",
                (18, 9): "内陆十字路",
                (24, 9): "德军纵深",
            }.get((q, r), "")
            row["label"] = label
            if label and t == "water":
                row["terrain"] = "plains"
            tiles.append(row)
    return tiles


def map_normandy_breakout(w: int = 32, h: int = 20) -> list[dict]:
    """Saint-Lô / COBRA: dense bocage, road net south, town hub."""
    tiles = []
    for r in range(h):
        for q in range(w):
            t = "bocage" if (q + r * 2) % 4 < 2 else "plains"
            if (q * 3 + r) % 9 == 0:
                t = "forest"
            if q >= 24 and (q - r) % 3 == 0:
                t = "hills"
            if 14 <= q <= 17 and 7 <= r <= 12:
                t = "plains"
            row = tile(q, r, t)
            if r in (6, 10, 14) or q in (8, 16, 22, 28):
                row["road"] = True
            if q == 20 and r % 5 == 2:
                row["river"] = True
                row["terrain"] = "water"
                row["bridge"] = r in (7, 12)
            label = {
                (6, 10): "盟军集结地",
                (16, 9): "圣洛",
                (20, 10): "马里尼",
                (26, 8): "装甲预备队",
                (26, 14): "库唐斯方向",
                (12, 6): "博卡日走廊",
            }.get((q, r), "")
            row["label"] = label
            if label and row["terrain"] == "water":
                row["terrain"] = "plains"
            tiles.append(row)
    return tiles


def map_sinai(w: int = 30, h: int = 18) -> list[dict]:
    """Suez Canal west-east: canal strip, east-bank lodgment, Sinai depth."""
    tiles = []
    for r in range(h):
        for q in range(w):
            t = "desert"
            if q in (7, 8):
                t = "water"
            elif 9 <= q <= 12 and (r + q) % 5 == 0:
                t = "marsh"  # salt pans / canal belt
            elif q >= 20 and (q + r) % 6 == 0:
                t = "hills"
            elif (q + 2 * r) % 13 == 0:
                t = "hills"
            row = tile(q, r, t)
            if q in (7, 8) and r in (4, 9, 14):
                row["bridge"] = True
                row["terrain"] = "water"
                row["river"] = True
            if r in (4, 9, 14) or q in (5, 10, 16, 22, 27):
                row["road"] = True
            label = {
                (5, 4): "埃军西岸",
                (5, 14): "运河防线",
                (10, 4): "伊斯梅利亚",
                (10, 9): "中国农场",
                (10, 14): "德韦索尔",
                (7, 4): "北桥",
                (7, 9): "中央桥",
                (7, 14): "南桥",
                (18, 9): "反突击出发线",
                (26, 9): "以军纵深",
            }.get((q, r), "")
            row["label"] = label
            if label and row["terrain"] == "water" and not row.get("bridge"):
                # keep canal tiles as water except bridges already handled
                pass
            tiles.append(row)
    return tiles


def map_golan(w: int = 24, h: int = 18) -> list[dict]:
    """Eastern slopes → ridge → western reserves."""
    tiles = []
    for r in range(h):
        for q in range(w):
            t = "plains"
            if q <= 4:
                t = "desert" if (q + r) % 3 else "hills"
            elif 8 <= q <= 15:
                t = "hills" if (q + r) % 3 else "mountain"
            elif q >= 16:
                t = "plains" if (q + r) % 4 else "hills"
            if 10 <= q <= 13 and r % 5 == 2:
                t = "mountain"
            row = tile(q, r, t)
            if r in (5, 9, 13) or q in (6, 12, 18):
                row["road"] = True
            if q == 17 and r in (8, 9):
                row["river"] = True
                row["terrain"] = "water"
                row["bridge"] = r == 9
            label = {
                (2, 9): "叙军出发地",
                (10, 4): "泪谷",
                (12, 9): "库奈特拉",
                (12, 14): "纳法赫",
                (18, 9): "预备队集结",
                (6, 5): "东坡通道",
                (6, 13): "南线通道",
            }.get((q, r), "")
            row["label"] = label
            if label and row["terrain"] == "water":
                row["terrain"] = "hills"
            tiles.append(row)
    return tiles


def map_gulf_west(w: int = 36, h: int = 22) -> list[dict]:
    """Open desert maneuver with Wadi al-Batin as a linear obstacle."""
    tiles = []
    for r in range(h):
        for q in range(w):
            t = "desert"
            if (q + r) % 7 == 0:
                t = "hills"
            if abs(q - 12) <= 0 and 2 <= r <= 19:
                t = "hills"  # wadi belt (not impassable)
            if (q - r) % 11 == 0:
                t = "plains"
            row = tile(q, r, t)
            if r in (6, 11, 16) or q in (8, 18, 28):
                row["road"] = True
            if q == 12:
                row["road"] = True
            label = {
                (4, 16): "多国部队集结",
                (12, 11): "瓦迪巴廷",
                (20, 8): "73东区",
                (26, 12): "诺福克目标",
                (32, 10): "伊军纵深",
                (22, 16): "南翼机动轴",
            }.get((q, r), "")
            row["label"] = label
            tiles.append(row)
    return tiles


def map_gulf_kuwait(w: int = 30, h: int = 20) -> list[dict]:
    """Coastal city, fortified belt, breach corridors."""
    tiles = []
    for r in range(h):
        for q in range(w):
            t = "desert"
            if q >= 26:
                t = "water"  # Persian Gulf
            elif q >= 24:
                t = "plains"
            if 14 <= q <= 18 and (r % 4 == 1 or r % 4 == 2):
                t = "hills"  # fortified belt abstraction
            if (q, r) in {(24, 8), (24, 12), (25, 10)}:
                t = "city"
            if (q + r) % 9 == 0 and q < 14:
                t = "hills"
            row = tile(q, r, t)
            if r in (7, 11, 15) or q in (6, 16, 22, 24):
                row["road"] = True
            if q == 16 and r in (7, 11, 15):
                row["road"] = True
                if row["terrain"] == "water":
                    row["terrain"] = "hills"
            label = {
                (4, 11): "联军进攻出发",
                (14, 7): "北突破口",
                (16, 11): "筑垒带",
                (14, 15): "南突破口",
                (24, 10): "科威特城",
                (24, 7): "贾赫拉",
                (25, 13): "国际机场",
                (20, 11): "北向通道",
            }.get((q, r), "")
            row["label"] = label
            if label and row["terrain"] == "water":
                row["terrain"] = "city" if "科威特" in label else "plains"
            tiles.append(row)
    return tiles


# ---------------------------------------------------------------------------
# Rosters (explicit type/size; front/date-scoped)
# ---------------------------------------------------------------------------

def roster_tutorial() -> tuple[list[dict], list[dict]]:
    blue = place_list(
        [
            ("蓝方指挥部", "hq", "brigade", 1, 3),
            ("第1机械化营", "mechanized", "battalion", 2, 2),
            ("第2装甲连", "armor", "battalion", 2, 5),
            ("第3步兵营", "infantry", "battalion", 2, 7),
            ("炮兵连", "artillery", "battalion", 1, 6),
            ("工兵排", "engineer", "battalion", 3, 4),
        ],
        0,
    )
    red = place_list(
        [
            ("红方指挥部", "hq", "brigade", 12, 5),
            ("警戒装甲排", "armor", "battalion", 11, 3),
            ("前沿步兵连", "infantry", "battalion", 11, 7),
            ("反坦克组", "infantry", "battalion", 10, 5),
            ("观察哨", "recon", "battalion", 12, 8),
        ],
        1,
        start_idx=10,
    )
    return blue, red


def roster_normandy_bridgehead() -> tuple[list[dict], list[dict]]:
    """June 6 Utah / Cotentin — no 4th Armored (landed 11 July)."""
    us = place_list(
        [
            ("VII Corps HQ", "hq", "corps", 3, 2),
            ("4th Infantry Division", "infantry", "division", 4, 5),
            ("82nd Airborne Division", "airborne", "division", 8, 3),
            ("101st Airborne Division", "airborne", "division", 8, 7),
            ("90th Infantry Division", "infantry", "division", 4, 12),
            ("1st Engineer Special Brigade", "engineer", "brigade", 3, 9),
            ("2nd Ranger Battalion", "infantry", "battalion", 3, 14),
            ("VII Corps Artillery", "artillery", "brigade", 5, 10),
        ],
        0,
    )
    de = place_list(
        [
            ("Seventh Army", "hq", "army", 24, 9),
            ("709th Infantry Division", "infantry", "division", 18, 5),
            ("243rd Infantry Division", "infantry", "division", 18, 12),
            ("91st Air Landing Division", "infantry", "division", 20, 8),
            ("352nd Infantry Division", "infantry", "division", 16, 10),
            ("6th Parachute Regiment", "infantry", "regiment", 14, 4),
            ("Mobile Brigade 30", "motorized", "brigade", 22, 13),
            ("LXXXIV Corps Artillery", "artillery", "brigade", 22, 6),
        ],
        1,
        start_idx=20,
    )
    return us, de


def roster_normandy_breakout() -> tuple[list[dict], list[dict]]:
    """Late July COBRA — armor present, distinct from June 6 list."""
    us = place_list(
        [
            ("VII Corps", "hq", "corps", 5, 10),
            ("1st Infantry Division", "infantry", "division", 8, 6),
            ("9th Infantry Division", "infantry", "division", 8, 14),
            ("30th Infantry Division", "infantry", "division", 10, 10),
            ("2nd Armored Division", "armor", "division", 7, 8),
            ("3rd Armored Division", "armor", "division", 7, 12),
            ("2nd Armored Cavalry Regiment", "recon", "regiment", 11, 4),
            ("VII Corps Artillery", "artillery", "brigade", 5, 14),
        ],
        0,
    )
    de = place_list(
        [
            ("Panzer Group West", "hq", "army", 28, 10),
            ("Panzer Lehr Division", "armor", "division", 22, 8),
            ("2nd SS Panzer Division", "armor", "division", 24, 12),
            ("17th SS Panzergrenadier Division", "mechanized", "division", 20, 6),
            ("353rd Infantry Division", "infantry", "division", 18, 12),
            ("5th Parachute Division", "infantry", "division", 19, 15),
            ("275th Infantry Division", "infantry", "division", 16, 8),
            ("LXXXIV Corps Artillery", "artillery", "brigade", 26, 7),
        ],
        1,
        start_idx=20,
    )
    return us, de


def roster_sinai() -> tuple[list[dict], list[dict]]:
    """Sinai canal front — 162nd/252nd/143rd style Israeli counterattack set;
    NOT the Golan 7th/188th/7th Brigade set.
    """
    il = place_list(
        [
            ("Southern Command", "hq", "army", 26, 2),
            ("162nd Armored Division", "armor", "division", 24, 6),
            ("143rd Armored Division", "armor", "division", 24, 12),
            ("252nd Armored Division", "armor", "division", 22, 9),
            ("600th Armored Brigade", "armor", "brigade", 20, 4),
            ("205th Armored Brigade", "armor", "brigade", 20, 14),
            ("14th Armored Brigade", "armor", "brigade", 18, 9),
            ("421st Reconnaissance Battalion", "recon", "battalion", 16, 6),
            ("Artillery Group Sinai", "artillery", "brigade", 25, 15),
        ],
        0,
    )
    eg = place_list(
        [
            ("Second Field Army", "hq", "army", 3, 3),
            ("16th Infantry Division", "infantry", "division", 10, 3),
            ("18th Infantry Division", "infantry", "division", 10, 15),
            ("2nd Infantry Division", "infantry", "division", 5, 8),
            ("4th Armored Division", "armor", "division", 4, 12),
            ("21st Armored Division", "armor", "division", 2, 6),
            ("130th Amphibious Brigade", "mechanized", "brigade", 11, 9),
            ("25th Independent Armored Brigade", "armor", "brigade", 12, 5),
            ("Sa'iqa Group 127", "infantry", "regiment", 12, 13),
            ("Army Artillery West", "artillery", "brigade", 2, 16),
            ("Air Defense Command", "air_defense", "brigade", 4, 1),
        ],
        1,
        start_idx=20,
    )
    return il, eg


def roster_golan() -> tuple[list[dict], list[dict]]:
    """Northern Golan — 7th/188th/7th Brigade; Sinai corps stay out."""
    il = place_list(
        [
            ("Northern Command", "hq", "army", 20, 2),
            ("7th Armored Brigade", "armor", "brigade", 18, 5),
            ("188th Barak Armored Brigade", "armor", "brigade", 18, 10),
            ("Golani Infantry Brigade", "infantry", "brigade", 17, 14),
            ("Reserve Armor Column", "armor", "brigade", 21, 9),
            ("Northern Artillery", "artillery", "brigade", 19, 7),
            ("Recon Troop North", "recon", "battalion", 16, 12),
        ],
        0,
    )
    sy = place_list(
        [
            ("Syrian 5th Infantry Division", "infantry", "division", 4, 4),
            ("Syrian 9th Infantry Division", "infantry", "division", 4, 14),
            ("Syrian 1st Armored Division", "armor", "division", 3, 8),
            ("Syrian 3rd Armored Division", "armor", "division", 2, 11),
            ("Syrian 47th Independent Armored Brigade", "armor", "brigade", 6, 6),
            ("Syrian 81st Armored Brigade", "armor", "brigade", 6, 13),
            ("Syrian 121st Mechanized Brigade", "mechanized", "brigade", 5, 10),
            ("Syrian Air Defense Command", "air_defense", "brigade", 1, 2),
        ],
        1,
        start_idx=20,
    )
    return il, sy


def roster_gulf_west() -> tuple[list[dict], list[dict]]:
    coal = place_list(
        [
            ("VII Corps", "hq", "corps", 3, 18),
            ("1st Armored Division", "armor", "division", 6, 14),
            ("3rd Armored Division", "armor", "division", 6, 18),
            ("1st Cavalry Division", "mechanized", "division", 5, 10),
            ("2nd Armored Cavalry Regiment", "recon", "regiment", 9, 8),
            ("3rd Armored Cavalry Regiment", "recon", "regiment", 9, 16),
            ("1st Infantry Division (Mechanized)", "mechanized", "division", 7, 6),
            ("210th Field Artillery Brigade", "artillery", "brigade", 4, 12),
            ("XVIII Airborne Corps", "hq", "corps", 2, 8),
            ("24th Infantry Division (Mechanized)", "mechanized", "division", 5, 4),
        ],
        0,
    )
    irq = place_list(
        [
            ("Iraqi III Corps", "hq", "corps", 32, 12),
            ("Tawakalna Republican Guard Division", "armor", "division", 28, 8),
            ("Medina Republican Guard Division", "armor", "division", 28, 14),
            ("Hammurabi Republican Guard Division", "mechanized", "division", 30, 10),
            ("26th Infantry Division", "infantry", "division", 22, 6),
            ("31st Infantry Division", "infantry", "division", 22, 16),
            ("48th Infantry Division", "infantry", "division", 20, 11),
            ("5th Mechanized Division", "mechanized", "division", 25, 4),
            ("Iraqi Corps Artillery", "artillery", "brigade", 31, 18),
        ],
        1,
        start_idx=20,
    )
    return coal, irq


def roster_gulf_kuwait() -> tuple[list[dict], list[dict]]:
    coal = place_list(
        [
            ("Marine Forces", "hq", "corps", 3, 11),
            ("1st Marine Division", "mechanized", "division", 6, 8),
            ("2nd Marine Division", "mechanized", "division", 6, 14),
            ("British 1st Armoured Division", "armor", "division", 5, 5),
            ("6th French Light Armored Division", "armor", "brigade", 5, 17),
            ("Tiger Brigade, 2nd Armored Division", "armor", "brigade", 8, 11),
            ("Joint Recon Squadron", "recon", "regiment", 10, 7),
            ("Naval Gunfire / Corps Artillery", "artillery", "brigade", 4, 11),
            ("Engineer Breach Group", "engineer", "brigade", 9, 13),
        ],
        0,
    )
    irq = place_list(
        [
            ("Iraqi III Corps Kuwait", "hq", "corps", 23, 10),
            ("1st Mechanized Division", "mechanized", "division", 18, 6),
            ("3rd Armored Division", "armor", "division", 19, 12),
            ("5th Mechanized Division", "mechanized", "division", 16, 10),
            ("14th Infantry Division", "infantry", "division", 21, 8),
            ("7th Infantry Division", "infantry", "division", 21, 14),
            ("Fatah Brigade Guard", "infantry", "brigade", 22, 10),
            ("Corps Artillery", "artillery", "brigade", 24, 16),
        ],
        1,
        start_idx=20,
    )
    return coal, irq


# ---------------------------------------------------------------------------
# Scenario builders
# ---------------------------------------------------------------------------

def build_tutorial() -> dict:
    tiles = map_tutorial()
    blue, red = roster_tutorial()
    objectives = [
        {"q": 5, "r": 4, "name": "河谷集镇", "value": 10, "owner": -1},
        {"q": 8, "r": 5, "name": "东岸要点", "value": 12, "owner": -1},
        {"q": 9, "r": 2, "name": "北部观察点", "value": 8, "owner": 1},
    ]
    depots = [
        {"q": 1, "r": 4, "side": 0, "capacity": 100},
        {"q": 12, "r": 5, "side": 1, "capacity": 80},
    ]
    note = (
        "虚构教学演习。双方分列河谷东西，便于练习选中、下令、过桥、侦察与补给。"
        "单位名称仅帮助识别兵种；所有态势与数值均为教学设计。"
        + DESIGN_NOTE
    )
    return scenario_shell(
        "tutorial", "沙盘入门", "边境河谷演习", "modern", "1991-01-01",
        14, 10, 4, 4, 6, 7,
        "学习侦察、补给、命令与同时回合结算。蓝方自西向东夺取集镇与东岸要点；红方迟滞并固守观察点。\n"
        "分步练习：1) 选中蓝方单位查看档案；2) 下达「机动/侦察」指向河谷集镇；3) 让工兵过桥；"
        "4) 为炮兵分配支援；5) 锁定命令，观察同时结算与补给变化。",
        "蓝方", "#587B8D", "红方", "#C5523A",
        tiles, blue + red, objectives, depots, "tutorial", design_notes=note,
    )


def build_normandy_bridgehead() -> dict:
    tiles = map_normandy_bridgehead()
    us, de = roster_normandy_bridgehead()
    objectives = [
        {"q": 7, "r": 5, "name": "Causeway 1 出口", "value": 12, "owner": 0},
        {"q": 12, "r": 4, "name": "圣梅尔埃格利斯", "value": 14, "owner": -1},
        {"q": 12, "r": 12, "name": "卡朗唐", "value": 16, "owner": -1},
        {"q": 18, "r": 9, "name": "内陆十字路", "value": 10, "owner": -1},
    ]
    depots = [
        {"q": 3, "r": 9, "side": 0, "capacity": 90},
        {"q": 24, "r": 9, "side": 1, "capacity": 110},
    ]
    return scenario_shell(
        "normandy_bridgehead", "诺曼底桥头堡", "犹他海滩至科唐坦",
        "ww2", "1944-06-06", 28, 18, 2, 6, 12, 440606,
        "盟军自犹他滩头经堤道打通出口并夺取内陆要点；德军依托湿地与博卡日迟滞。本关编制限于 6 月 6 日前后犹他/科唐坦方向公开番号（不含 7 月才上岸的装甲师）。",
        "美军", "#587B8D", "德军", "#C5523A",
        tiles, us + de, objectives, depots, "normandy_utm",
    )


def build_normandy_breakout() -> dict:
    tiles = map_normandy_breakout()
    us, de = roster_normandy_breakout()
    objectives = [
        {"q": 16, "r": 9, "name": "圣洛", "value": 14, "owner": 1},
        {"q": 20, "r": 10, "name": "马里尼", "value": 12, "owner": -1},
        {"q": 26, "r": 8, "name": "装甲预备队阵地", "value": 10, "owner": 1},
        {"q": 26, "r": 14, "name": "库唐斯方向道路", "value": 12, "owner": -1},
    ]
    depots = [
        {"q": 5, "r": 10, "side": 0, "capacity": 120},
        {"q": 29, "r": 10, "side": 1, "capacity": 100},
    ]
    return scenario_shell(
        "normandy_breakout", "诺曼底突破", "圣洛以西的突破战",
        "ww2", "1944-07-25", 32, 20, 2, 6, 12, 440725,
        "盟军在圣洛方向撕开博卡日并沿道路南下；德军以装甲预备队封堵。编制限于 7 月下旬突破阶段可用的师/军单位。",
        "美军", "#587B8D", "德军", "#C5523A",
        tiles, us + de, objectives, depots, "normandy_cobra",
        reinforcements=[
            {
                "turn": 4,
                "unit": formation("装甲预备队加强连", "armor", "battalion", 1, 28, 12, idx=40, strength=85, organization=90),
            }
        ],
        extra={"weather": "clear", "night_cycle": False},
    )


def build_sinai() -> dict:
    tiles = map_sinai()
    il, eg = roster_sinai()
    # Egypt holds west bank + east-bank lodgments; Israel deeper in Sinai counterattacks.
    # Shift Israeli units east of canal lodgment, Egyptian combat on/behind canal.
    objectives = [
        {"q": 10, "r": 4, "name": "伊斯梅利亚桥头", "value": 12, "owner": 1},
        {"q": 10, "r": 9, "name": "中国农场", "value": 16, "owner": -1},
        {"q": 10, "r": 14, "name": "德韦索尔渡口", "value": 12, "owner": 1},
        {"q": 7, "r": 9, "name": "运河中央桥", "value": 14, "owner": -1},
    ]
    depots = [
        {"q": 27, "r": 9, "side": 0, "capacity": 140},
        {"q": 3, "r": 9, "side": 1, "capacity": 140},
    ]
    return scenario_shell(
        "sinai_1973", "西奈运河战线", "渡河桥头堡与反突击",
        "coldwar", "1973-10-06", 30, 18, 4, 6, 12, 731006,
        "埃及军已在运河东岸建立桥头堡并依托西岸补给；以军装甲师自西奈纵深向运河反击，争夺渡口与中国农场。编制限于西奈方向公开番号（戈兰第 7 装甲旅等不在此关）。",
        "以色列国防军", "#587B8D", "埃及军", "#C5523A",
        tiles, il + eg, objectives, depots, "sinai",
        reinforcements=[
            {
                "turn": 3,
                "unit": formation("增援装甲旅", "armor", "brigade", 0, 28, 9, idx=40, strength=92, organization=88),
            }
        ],
        extra={"weather": "clear", "night_cycle": True, "start_hour": 6},
    )


def build_golan() -> dict:
    tiles = map_golan()
    il, sy = roster_golan()
    objectives = [
        {"q": 10, "r": 4, "name": "泪谷", "value": 14, "owner": 0},
        {"q": 12, "r": 9, "name": "库奈特拉", "value": 16, "owner": 0},
        {"q": 12, "r": 14, "name": "纳法赫", "value": 12, "owner": -1},
        {"q": 6, "r": 9, "name": "东坡通道", "value": 10, "owner": -1},
    ]
    depots = [
        {"q": 21, "r": 9, "side": 0, "capacity": 100},
        {"q": 1, "r": 9, "side": 1, "capacity": 120},
    ]
    return scenario_shell(
        "golan_1973", "戈兰高地", "高地防御与预备队",
        "coldwar", "1973-10-06", 24, 18, 3, 6, 12, 731007,
        "叙军沿东坡向山脊推进；以军第 7 装甲旅与第 188 旅依托库奈特拉—纳法赫轴线固守并等待预备队。编制限于北方战线，不含西奈装甲师。",
        "以色列国防军", "#587B8D", "叙利亚军", "#C5523A",
        tiles, il + sy, objectives, depots, "golan",
        reinforcements=[
            {
                "turn": 2,
                "unit": formation("预备装甲营", "armor", "battalion", 0, 21, 14, idx=40, strength=90, organization=85),
            }
        ],
        extra={"weather": "clear", "night_cycle": False},
    )


def build_gulf_west() -> dict:
    tiles = map_gulf_west()
    coal, irq = roster_gulf_west()
    objectives = [
        {"q": 12, "r": 11, "name": "瓦迪巴廷", "value": 10, "owner": -1},
        {"q": 20, "r": 8, "name": "73 东区", "value": 14, "owner": 1},
        {"q": 26, "r": 12, "name": "诺福克目标", "value": 16, "owner": 1},
        {"q": 22, "r": 16, "name": "南翼机动轴", "value": 10, "owner": -1},
    ]
    depots = [
        {"q": 2, "r": 12, "side": 0, "capacity": 160},
        {"q": 34, "r": 12, "side": 1, "capacity": 120},
    ]
    return scenario_shell(
        "gulf_west", "沙漠左钩拳", "西部纵深机动",
        "modern", "1991-02-24", 36, 22, 8, 6, 12, 910224,
        "第 VII 军与第 XVIII 空降军自西侧实施纵深勾拳，越过瓦迪巴廷并夺取共和卫队防御要点；伊军保持交通线并组织纵深防御。",
        "多国部队", "#587B8D", "伊拉克军", "#C5523A",
        tiles, coal + irq, objectives, depots, "gulf",
    )


def build_gulf_kuwait() -> dict:
    tiles = map_gulf_kuwait()
    coal, irq = roster_gulf_kuwait()
    objectives = [
        {"q": 14, "r": 7, "name": "北突破口", "value": 12, "owner": -1},
        {"q": 16, "r": 11, "name": "筑垒带中央", "value": 14, "owner": 1},
        {"q": 14, "r": 15, "name": "南突破口", "value": 12, "owner": -1},
        {"q": 24, "r": 10, "name": "科威特城", "value": 18, "owner": 1},
        {"q": 25, "r": 13, "name": "国际机场", "value": 10, "owner": 1},
    ]
    depots = [
        {"q": 2, "r": 11, "side": 0, "capacity": 140},
        {"q": 23, "r": 5, "side": 1, "capacity": 90},
    ]
    return scenario_shell(
        "gulf_kuwait", "科威特地面战", "突破筑垒带与解放通道",
        "modern", "1991-02-24", 30, 20, 5, 6, 12, 910225,
        "联军自南与西突破伊军筑垒带，沿海岸与北向通道解放科威特城；伊军延缓突破并保持退路。地图含海岸、城市与筑垒带抽象，与沙漠左钩拳的开阔机动明显不同。",
        "联军", "#587B8D", "伊拉克军", "#C5523A",
        tiles, coal + irq, objectives, depots, "kuwait",
    )


BUILDERS = [
    build_tutorial,
    build_normandy_bridgehead,
    build_normandy_breakout,
    build_sinai,
    build_golan,
    build_gulf_west,
    build_gulf_kuwait,
]


def build() -> list[dict]:
    OUT.mkdir(parents=True, exist_ok=True)
    scenarios = []
    for fn in BUILDERS:
        s = fn()
        path = OUT / f"{s['id']}.json"
        path.write_text(json.dumps(s, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        scenarios.append(s)
        print(f"wrote {path.name}: units={len(s['units'])} tiles={len(s['tiles'])}")
    return scenarios


def walkable_neighbors(tile_at: dict, q: int, r: int) -> list[tuple[int, int]]:
    dirs = [(1, 0), (1, -1), (0, -1), (-1, 0), (-1, 1), (0, 1)]
    out = []
    for dq, dr in dirs:
        t = tile_at.get((q + dq, r + dr))
        if not t:
            continue
        if t.get("terrain") == "water" and not t.get("bridge"):
            continue
        out.append((q + dq, r + dr))
    return out


def land_connected(tiles: list[dict]) -> bool:
    tile_at = {(t["q"], t["r"]): t for t in tiles}
    starts = [p for p, t in tile_at.items() if not (t.get("terrain") == "water" and not t.get("bridge"))]
    if not starts:
        return False
    seen = {starts[0]}
    dq = deque([starts[0]])
    while dq:
        q, r = dq.popleft()
        for n in walkable_neighbors(tile_at, q, r):
            if n not in seen:
                seen.add(n)
                dq.append(n)
    return all(p in seen for p in starts)


def passable(tile_at: dict, q: int, r: int) -> bool:
    t = tile_at.get((q, r))
    if not t:
        return False
    if t.get("terrain") == "water" and not t.get("bridge"):
        return False
    return True


def validate() -> list[str]:
    errors: list[str] = []
    files = sorted(OUT.glob("*.json"))
    if len(files) != 7:
        errors.append(f"expected 7 scenarios, found {len(files)}")
    all_labels: dict[str, set] = {}
    all_obj_names: dict[str, set] = {}
    for f in files:
        try:
            s = json.loads(f.read_text(encoding="utf-8"))
        except Exception as e:  # noqa: BLE001
            errors.append(f"{f.name}: invalid JSON: {e}")
            continue
        w, h = s["width"], s["height"]
        coords: set[tuple[int, int]] = set()
        tile_at: dict[tuple[int, int], dict] = {}
        ids: set[str] = set()
        for t in s["tiles"]:
            pos = (t["q"], t["r"])
            if pos in coords:
                errors.append(f"{f.name}: duplicate tile {pos}")
            coords.add(pos)
            tile_at[pos] = t
            if t["terrain"] not in TERRAINS:
                errors.append(f"{f.name}: bad terrain {t.get('terrain')}")
            if not (0 <= t["q"] < w and 0 <= t["r"] < h):
                errors.append(f"{f.name}: tile off map {pos}")
        if len(coords) != w * h:
            errors.append(f"{f.name}: expected {w * h} tiles, got {len(coords)}")
        if not land_connected(s["tiles"]):
            errors.append(f"{f.name}: walkable land not fully connected")

        for u in s["units"]:
            if u["id"] in ids:
                errors.append(f"{f.name}: duplicate unit id {u['id']}")
            ids.add(u["id"])
            pos = (u["q"], u["r"])
            if pos not in coords:
                errors.append(f"{f.name}: off-map unit {u['id']}")
            elif not passable(tile_at, u["q"], u["r"]):
                errors.append(f"{f.name}: unit {u['id']} on impassable tile {pos} terrain={tile_at[pos].get('terrain')}")
            if u["type"] not in TYPES:
                errors.append(f"{f.name}: bad unit type {u.get('type')} for {u['id']}")
            if int(u.get("side", -1)) not in (0, 1):
                errors.append(f"{f.name}: bad side for {u['id']}")

        units = s["units"]
        hq = sum(1 for u in units if u.get("type") == "hq")
        combat = sum(1 for u in units if u.get("type") not in ("hq", "logistics"))
        if s["id"] == "tutorial":
            if combat < 8:
                errors.append(f"{f.name}: tutorial needs >=8 combat-capable units, has {combat}")
            if hq > 3:
                errors.append(f"{f.name}: tutorial too many HQ ({hq})")
        else:
            if combat < 10:
                errors.append(f"{f.name}: too few combat units ({combat})")
            if hq > max(4, len(units) // 4):
                errors.append(f"{f.name}: excessive HQ ratio {hq}/{len(units)}")

        for d in s.get("depots", []):
            if not passable(tile_at, d["q"], d["r"]):
                errors.append(f"{f.name}: depot on impassable {(d['q'], d['r'])}")
            if int(d.get("side", -1)) not in (0, 1):
                errors.append(f"{f.name}: depot bad side")

        for o in s.get("objectives", []):
            if not passable(tile_at, o["q"], o["r"]):
                errors.append(f"{f.name}: objective on impassable {(o['q'], o['r'])}")
            owner = int(o.get("owner", -1))
            if owner not in (-1, 0, 1):
                errors.append(f"{f.name}: objective bad owner {owner}")

        for rf in s.get("reinforcements", []):
            u = rf.get("unit", {})
            if not passable(tile_at, u.get("q", -1), u.get("r", -1)):
                errors.append(f"{f.name}: reinforcement spawn impassable {u.get('id')}")

        # Side presence
        sides_present = {int(u["side"]) for u in units}
        if sides_present != {0, 1}:
            errors.append(f"{f.name}: both sides required, found {sides_present}")

        # Identity: labels and objective names must not be a shared generic template
        labels = {t.get("label") for t in s["tiles"] if t.get("label")}
        objs = {o.get("name") for o in s.get("objectives", [])}
        all_labels[s["id"]] = labels
        all_obj_names[s["id"]] = objs
        if s["id"] != "tutorial":
            if len(labels) < 4:
                errors.append(f"{f.name}: too few distinctive labels ({len(labels)})")
            if len(objs) < 3:
                errors.append(f"{f.name}: too few objectives")

        # Description must mention scenario identity
        if not str(s.get("description", "")).strip():
            errors.append(f"{f.name}: missing description")

        # era_rules keys expected by engine
        er = s.get("era_rules", {})
        for key in ("recon_range", "antitank"):
            if key not in er:
                errors.append(f"{f.name}: era_rules missing {key}")

    # Cross-scenario: objective name sets should not all be identical
    non_tut = [k for k in all_obj_names if k != "tutorial"]
    if non_tut:
        shared = all_obj_names[non_tut[0]]
        identical = all(all_obj_names[k] == shared for k in non_tut)
        if identical:
            errors.append("all non-tutorial scenarios share identical objective names (generic template)")
    return errors


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("command", choices=["build", "validate", "all"], nargs="?", default="all")
    args = ap.parse_args()
    if args.command in ("build", "all"):
        build()
    errors = validate() if args.command in ("validate", "all") else validate()
    if errors:
        print(f"CONTENT FAIL: {len(errors)} errors")
        for e in errors:
            print(" -", e)
        return 1
    print("CONTENT PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
