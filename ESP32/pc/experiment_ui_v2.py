#!/usr/bin/env python3
"""Clearly named launcher for the improved CSI experiment and comparison UI."""

import tkinter as tk

from experiment_ui import ExperimentApp


def main() -> None:
    root = tk.Tk()
    ExperimentApp(root, app_title="ESP32 Wi-Fi CSI 실험실 V2 - 비교 분석 개선판")
    root.mainloop()


if __name__ == "__main__":
    main()
