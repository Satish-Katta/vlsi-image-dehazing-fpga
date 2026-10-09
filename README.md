# vlsi-image-dehazing-fpga
Hardware-efficient image dehazing using Dark Channel Prior and saturation-based transmission on Zynq-7000 FPGA (MATLAB + Verilog)
# VLSI Implementation of Image Dehazing Algorithms

Hardware-efficient image dehazing on FPGA using Dark Channel Prior (DCP)
with saturation-based transmission estimation.

## 📌 Overview
Haze reduces image contrast and color quality. This project implements a
real-time dehazing pipeline using a 5×5 minimum filter on a downsampled
image, validated in MATLAB and implemented in Verilog HDL on a Zynq-7000 FPGA.

## ✨ Key Features
- 5×5 minimum filter for atmospheric light estimation
- Saturation-driven pixel-level transmission (reduces halo artifacts)
- Reciprocal LUT (no divider) and Gamma LUT
- 7-stage pipelined architecture
- 12-bit fixed-point (Q0.12)

## 🏗 Architecture
![Block Diagram](docs/fig2_block_diagram.png)

## 📊 Results
| Metric | Value |
|---|---|
| Device | Zynq-7000 (XC7Z020CLG484-1) |
| Frequency / Throughput | 85.2 MHz / 85.2 Mpixels/s |
| Slice LUTs | 2.49% |
| Slice Registers | 0.10% |
| Power | ~0.107 W |

PSNR/SSIM on SOTS (Outdoor): 23.83 / 0.9434

## 📁 Folder Structure
- `matlab/` – golden model
- `verilog/` – RTL and testbenches
- `images/` – input and output samples

## ▶️ How to Run
**MATLAB:** open `matlab/main.m` and run.
**Verilog:** open Vivado, add files from `verilog/src`, simulate with `verilog/tb`.

## 👨‍💻 Authors
K. Satish, N. Balaji – University College of Engineering Kakinada, JNTUK

## 📄 Citation
K. Satish and N. Balaji, "VLSI Implementation of Image Dehazing Algorithms," JETIR.
