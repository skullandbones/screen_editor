"""
Word count plugin for Python SE editor.
Counts lines, words, and characters in document or selected block.
"""

from se.plugin import PluginBase, HostAPI


class WordCountPlugin(PluginBase):
    """Word Count Statistics Plugin."""

    NAME = "WORDCNT"
    DESCRIPTION = "Document word, line, and character count"

    def run(self, api: HostAPI) -> bool:
        """Calculate and display statistics in a Tier 2 modal pop-up."""
        bounds = api.get_block_bounds()
        if bounds:
            r1, c1, r2, c2 = bounds
            total_lines = r2 - r1 + 1
            char_count = 0
            word_count = 0
            for r in range(r1, r2 + 1):
                line = api.checkout_line(r)
                sc = c1 if r == r1 else 0
                ec = c2 if r == r2 else len(line)
                span = line[sc:ec]
                char_count += len(span)
                word_count += len(span.split())
            scope = "Block"
        else:
            total_lines = api.get_total_lines()
            char_count = 0
            word_count = 0
            for r in range(total_lines):
                line = api.checkout_line(r)
                char_count += len(line)
                word_count += len(line.split())
            scope = "Document"

        stats = (
            f"{scope} Statistics:\n"
            f"  Lines     : {total_lines}\n"
            f"  Words     : {word_count}\n"
            f"  Characters: {char_count}"
        )
        api.show_modal("Word Count", stats)
        return True
