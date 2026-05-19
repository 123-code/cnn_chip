"""Update the Gowin pROM .v files' INIT_RAM_xx defparams from .mi files.

The pROM IPs are normally regenerated via the Gowin IDE wizard each time
weights change. This script does the same thing programmatically so we
don't need the GUI.
"""
import re

GOWIN = "/Applications/GowinIDE.app/Contents/Resources/Gowin_EDA/IDE/bin/cnn_chip/src/gowin_prom"
WEIGHTS_V  = f"{GOWIN}/weights_rom_module.v"
BIAS_V     = f"{GOWIN}/bias_rom_module.v"
WEIGHTS_MI = "/Users/joseignacio/cnn_chip/weights.mi"
BIAS_MI    = "/Users/joseignacio/cnn_chip/model/bias.mi"

def load_mi(path):
    """Return list of hex-string entries (without padding)."""
    out = []
    with open(path) as f:
        for line in f:
            s = line.strip()
            if not s or s.startswith("#"):
                continue
            out.append(s.upper())
    return out

def patch(v_path, mi_path, entries_per_word, char_width):
    """Rewrite INIT_RAM_xx defparams in a Gowin pROM .v file.

    entries_per_word = 256 // (char_width*4)  — how many entries per 256-bit word
    char_width = hex chars per entry
    """
    entries = load_mi(mi_path)
    pat = re.compile(
        r"defparam (\w+\.INIT_RAM_)([0-9A-Fa-f]+)\s*=\s*256'h([0-9A-Fa-f]+);"
    )
    with open(v_path) as f:
        text = f.read()

    def replace(m):
        prefix = m.group(1)        # e.g. "prom_inst_0.INIT_RAM_"
        idx = int(m.group(2), 16)  # word index
        base = idx * entries_per_word
        # Build the 256-bit constant: rightmost hex chars are the lowest address.
        chunk = []
        for k in range(entries_per_word):
            addr = base + k
            entry = entries[addr] if addr < len(entries) else "0" * char_width
            chunk.append(entry.zfill(char_width))
        # reverse so address 0 is rightmost
        hex_str = "".join(reversed(chunk))
        return f"defparam {prefix}{idx:02X} = 256'h{hex_str};"

    new = pat.sub(replace, text)
    with open(v_path, "w") as f:
        f.write(new)

# Weights ROM: 8-bit entries, 32 entries per 256-bit word
patch(WEIGHTS_V, WEIGHTS_MI, entries_per_word=32, char_width=2)
print(f"Patched {WEIGHTS_V} with {len(load_mi(WEIGHTS_MI))} weight bytes")

# Bias ROM: 32-bit entries, 8 entries per 256-bit word
patch(BIAS_V, BIAS_MI, entries_per_word=8, char_width=8)
print(f"Patched {BIAS_V} with {len(load_mi(BIAS_MI))} bias words")
