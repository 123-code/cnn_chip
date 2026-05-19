#!/bin/bash
# Flash the LED-version of cnn_chip with a specific digit baked in.
# Usage:  ./demo_flash.sh 7    (or any 0-9)
#
# Use this BEFORE each take of the FPGA so you start from a known state.

set -e
DIGIT="${1:-7}"

GOWIN_BASE=/Applications/GowinIDE.app/Contents/Resources/Gowin_EDA/IDE
PROJ=$GOWIN_BASE/bin/cnn_chip

# 1. Restore the LED-version top + control_unit + pins
cp $PROJ/src/_BACKUP_top_LED.v     $PROJ/src/top_mnist_accel.v
cp $PROJ/src/_BACKUP_control_LED.v $PROJ/src/control_unit.v
cp $PROJ/src/_BACKUP_pins_LED.cst  $PROJ/src/pins.cst

# 2. Sync the Gowin pROM .v files with the current .mi files (so the FPGA's
#    weights/biases match what the chip-sim in bake_image.py uses).
/Users/joseignacio/cnn_chip/venv/bin/python \
    /Users/joseignacio/cnn_chip/model/sync_roms.py

# 3. Bake the chosen digit into the SP IP
/Users/joseignacio/cnn_chip/venv/bin/python \
    /Users/joseignacio/cnn_chip/model/bake_image.py "$DIGIT"

# 3. Synthesize + Place & Route + bitstream
cd $PROJ
DYLD_FRAMEWORK_PATH=$GOWIN_BASE/lib \
DYLD_LIBRARY_PATH=$GOWIN_BASE/lib \
$GOWIN_BASE/bin/gw_sh /tmp/gw_build_led.tcl 2>&1 | tail -2

# 4. Flash to SRAM
$GOWIN_BASE/../Programmer/bin/programmer_cli \
    --device GW2AR-18C --operation_index 2 \
    --fsFile $PROJ/impl/pnr/project.fs 2>&1 | tail -2

echo ""
echo "============================================================"
echo "Flashed digit $DIGIT. Watch the LEDs:"
echo "  - LED5 should be blinking (heartbeat)"
echo "  - After ~1s, LED3 lights up (math_done)"
echo "  - Read the rest as a 4-bit binary digit (LEDs are active-low):"
echo "      LED4 = bit 3,  LED2 = bit 2,  LED1 = bit 1,  LED0 = bit 0"
echo "      LED on = bit 1, LED off = bit 0"
echo "============================================================"
