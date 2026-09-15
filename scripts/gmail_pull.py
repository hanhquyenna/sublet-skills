#!/usr/bin/env python3
"""Kéo email notification Facebook (facebookmail.com) qua IMAP -> JSON các post.

Env: SUBLET_IMAP_USER, SUBLET_IMAP_PASS (Gmail app password). Chạy được trên Mac hoặc Hetzner.
Usage: python3 scripts/gmail_pull.py [--since-days 1] [--mark-seen]
Output: JSON list [{message_id, received_at, subject, group_name, poster, snippet, post_url}]
"""
import imaplib, email, os, sys, json, re
from email.header import decode_header
from datetime import datetime, timedelta

HOST = os.environ.get("SUBLET_IMAP_HOST", "imap.gmail.com")
USER = os.environ.get("SUBLET_IMAP_USER")
PASS = os.environ.get("SUBLET_IMAP_PASS")

def dec(v):
    if not v: return ""
    parts = decode_header(v)
    return "".join(p.decode(enc or "utf-8", "ignore") if isinstance(p, bytes) else p for p, enc in parts)

def body_text(msg):
    if msg.is_multipart():
        for part in msg.walk():
            if part.get_content_type() == "text/plain":
                return part.get_payload(decode=True).decode(part.get_content_charset() or "utf-8", "ignore")
        for part in msg.walk():
            if part.get_content_type() == "text/html":
                html = part.get_payload(decode=True).decode(part.get_content_charset() or "utf-8", "ignore")
                return re.sub(r"<[^>]+>", " ", html)
    return msg.get_payload(decode=True).decode(msg.get_content_charset() or "utf-8", "ignore")

def main():
    if not USER or not PASS:
        sys.exit("set SUBLET_IMAP_USER and SUBLET_IMAP_PASS")
    since_days = 1; mark_seen = "--mark-seen" in sys.argv
    if "--since-days" in sys.argv:
        since_days = int(sys.argv[sys.argv.index("--since-days") + 1])
    since = (datetime.utcnow() - timedelta(days=since_days)).strftime("%d-%b-%Y")
    M = imaplib.IMAP4_SSL(HOST); M.login(USER, PASS); M.select("INBOX")
    typ, data = M.search(None, f'(FROM "facebookmail.com" SINCE {since})')
    out = []
    for num in data[0].split():
        typ, raw = M.fetch(num, "(RFC822)")
        msg = email.message_from_bytes(raw[0][1])
        subj = dec(msg.get("Subject")); text = body_text(msg)
        # subject patterns: "<Poster> posted in <Group>" / "New post in <Group>"
        m = re.search(r"^(.*?) posted in (.+?)(?:\.|$)", subj)
        poster, group = (m.group(1), m.group(2)) if m else ("", subj)
        url = None
        for u in re.findall(r"https?://www\.facebook\.com/groups/[^\s\"'>]+", text):
            if "/posts/" in u or "permalink" in u:
                url = u.split("?")[0]; break
        snippet = re.sub(r"\s+", " ", text)[:1200]
        out.append({"message_id": msg.get("Message-ID"), "received_at": msg.get("Date"), "subject": subj,
                    "group_name": group, "poster": poster, "snippet": snippet, "post_url": url})
        if mark_seen: M.store(num, "+FLAGS", "\\Seen")
    M.logout()
    json.dump(out, sys.stdout, indent=2, ensure_ascii=False); print()

if __name__ == "__main__":
    main()
