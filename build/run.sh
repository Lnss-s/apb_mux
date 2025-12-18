#!/bin/bash

# Директория скрипта
curdir=$(pwd)
mkdir -p ${curdir}/work

echo "=== Creating temporary RTL with timescale ==="
echo '`timescale 1ns/1ps' | cat - ${curdir}/../rtl/apb_mux.sv > ${curdir}/apb_mux_xcelium.sv

echo "=== Compiling ==="
xrun -compile -64bit \
    ${curdir}/apb_mux_xcelium.sv ${curdir}/../tb/tb_apb_mux.sv \
    -xmlibdirpath ${curdir}/work -l ${curdir}/compile.log

if [ $? -ne 0 ]; then
    echo "ERROR: Compilation failed!"
    rm -f ${curdir}/apb_mux_xcelium.sv
    exit 1
fi

echo "=== Elaborating ==="
xrun -elaborate -elabonly -64bit -top tb_apb_mux_top -snapshot tb_apb_mux_top_opt \
    -xmlibdirpath ${curdir}/work -access +rwc -l ${curdir}/opt.log

if [ $? -ne 0 ]; then
    echo "ERROR: Elaboration failed!"
    rm -f ${curdir}/apb_mux_xcelium.sv
    exit 1
fi

echo "=== Running Simulation ==="
xrun -r tb_apb_mux_top_opt -64bit -xmlibdirpath ${curdir}/work \
    -seed 12345 -gui -l ${curdir}/run.log

# Удаляем временный файл
echo "=== Cleaning up temporary files ==="
rm -f ${curdir}/apb_mux_xcelium.sv

echo "=== Simulation completed ==="