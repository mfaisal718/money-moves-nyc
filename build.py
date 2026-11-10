#!/usr/bin/env python3
"""Builds public/index.html (the hosted game) from src/game.html.
src/game.html is the same file as the claude.ai artifact; this wraps it in a
full HTML page and loads config.js + the Supabase library first.
Run:  python3 build.py
"""
import pathlib
root = pathlib.Path(__file__).parent
game = (root / "src" / "game.html").read_text(encoding="utf-8")
head = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<style>:root{padding-top:env(safe-area-inset-top,0px);padding-bottom:env(safe-area-inset-bottom,0px)}body{margin:0;font:14px system-ui,sans-serif}img{max-width:100%}[hidden]{display:none!important}</style>
<script src="config.js"></script>
<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.45.4/dist/umd/supabase.js"></script>
</head>
<body>
"""
(root / "public" / "index.html").write_text(head + game + "\n</body>\n</html>\n", encoding="utf-8")
print("Built public/index.html")
