#!/usr/bin/env python3
"""scripts/gen-torrent.py — собрать .torrent для артефакта релиза PuraD.

Пишем торрент-файл сами, потому что mktorrent/transmission-create в окружении
могут отсутствовать. Получается обычный v1-торрент (bencoded) с публичными
трекерами: без флага `private`, чтобы раздача работала через DHT и без
собственного трекера.

Использование:
    scripts/gen-torrent.py <файл.iso> <файл.torrent> [--piece-mib 2] [--comment ...]
"""

import argparse
import hashlib
import os
import sys
import time

DEFAULT_TRACKERS = [
    "udp://tracker.opentrackr.org:1337/announce",
    "udp://open.tracker.cl:1337/announce",
    "udp://tracker.openbittorrent.com:6969/announce",
    "udp://exodus.desync.com:6969/announce",
    "udp://tracker.torrent.eu.org:451/announce",
]


def bencode(obj):
    if isinstance(obj, bool):
        raise TypeError("bool не кодируется в bencode")
    if isinstance(obj, int):
        return b"i%de" % obj
    if isinstance(obj, str):
        obj = obj.encode("utf-8")
    if isinstance(obj, bytes):
        return b"%d:%s" % (len(obj), obj)
    if isinstance(obj, list):
        return b"l" + b"".join(bencode(x) for x in obj) + b"e"
    if isinstance(obj, dict):
        out = b"d"
        for key in sorted(obj.keys()):
            out += bencode(key) + bencode(obj[key])
        return out + b"e"
    raise TypeError("неизвестный тип: %r" % type(obj))


def hash_pieces(path, piece_length):
    pieces = bytearray()
    count = 0
    with open(path, "rb") as fh:
        while True:
            chunk = fh.read(piece_length)
            if not chunk:
                break
            pieces += hashlib.sha1(chunk).digest()
            count += 1
    return bytes(pieces), count


def main():
    ap = argparse.ArgumentParser(description="Создать .torrent для артефакта PuraD")
    ap.add_argument("input", help="исходный файл (ISO)")
    ap.add_argument("output", help="куда записать .torrent")
    ap.add_argument("--piece-mib", type=int, default=2, help="размер куска в МиБ (по умолчанию 2)")
    ap.add_argument("--comment", default="", help="комментарий в торренте")
    ap.add_argument("--tracker", action="append", default=[], help="дополнительный трекер (можно несколько)")
    ap.add_argument("--web-seed", action="append", default=[],
                    help="URL web-seed (url-list, BEP 19); можно несколько раз")
    args = ap.parse_args()

    if not os.path.isfile(args.input):
        sys.exit("нет такого файла: %s" % args.input)

    piece_length = args.piece_mib * 1024 * 1024
    size = os.path.getsize(args.input)
    name = os.path.basename(args.input)

    print("==> хэширую %s (%d байт, куски по %d МиБ)" % (name, size, args.piece_mib))
    pieces, count = hash_pieces(args.input, piece_length)
    print("    кусков: %d" % count)

    trackers = list(dict.fromkeys(args.tracker + DEFAULT_TRACKERS))

    info = {
        "name": name,
        "length": size,
        "piece length": piece_length,
        "pieces": pieces,
    }
    meta = {
        "info": info,
        "announce": trackers[0],
        "announce-list": [[t] for t in trackers],
        "comment": args.comment or name,
        "created by": "PuraD scripts/gen-torrent.py",
        "creation date": int(time.time()),
    }
    if args.web_seed:
        meta["url-list"] = args.web_seed if len(args.web_seed) > 1 else args.web_seed[0]
        for ws in args.web_seed:
            print("    web-seed: %s" % ws)

    data = bencode(meta)
    with open(args.output, "wb") as fh:
        fh.write(data)

    print("==> записан %s (%d байт)" % (args.output, len(data)))
    print("    info-hash (sha1): %s" % hashlib.sha1(bencode(info)).hexdigest())


if __name__ == "__main__":
    main()
