"""
ROT13 cipher transformation plugin for Python SE editor.
Applies ROT13 to active block selection or current line.
"""

from se.plugin import PluginBase, HostAPI


def rot13_text(text: str) -> str:
    """Apply ROT13 caesar cipher shift to text."""
    result = []
    for ch in text:
        if "a" <= ch <= "z":
            result.append(chr((ord(ch) - ord("a") + 13) % 26 + ord("a")))
        elif "A" <= ch <= "Z":
            result.append(chr((ord(ch) - ord("A") + 13) % 26 + ord("A")))
        else:
            result.append(ch)
    return "".join(result)


class Rot13Plugin(PluginBase):
    """ROT13 Text Transformer Plugin."""

    NAME = "ROT13"
    DESCRIPTION = "Rotate letters by 13 positions (ROT13)"

    def run(self, api: HostAPI) -> bool:
        """Execute ROT13 on block selection or current line."""
        bounds = api.get_block_bounds()
        if bounds:
            r1, c1, r2, c2 = bounds
            for r in range(r1, r2 + 1):
                line = api.checkout_line(r)
                sc = c1 if r == r1 else 0
                ec = c2 if r == r2 else len(line)
                prefix = line[:sc]
                mid = rot13_text(line[sc:ec])
                suffix = line[ec:]
                api.commit_line(r, prefix + mid + suffix)
            api.set_status_msg("ROT13 applied to block")
        else:
            cur_r, _ = api.get_cursor()
            line = api.checkout_line(cur_r)
            api.commit_line(cur_r, rot13_text(line))
            api.set_status_msg("ROT13 applied to line")
        return True
