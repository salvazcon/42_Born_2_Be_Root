# Born_2_be_root - 11/10/2022

!# Just the Born_2_be_root :)

Documentacion - https://drive.google.com/drive/folders/1W3xtPNuVMlD9KfL1pCW4qMHRBYVVNFG8?usp=share_link


feat: migrate NDAS Simulator to multiprocessing and stabilize network and GUI

- Each Function runs in its own process, talking to the GUI through queues;
  state is kept across stop/restart.
- Simulated DataLoader moved to DataLoader.py (SIMULATE_DATALOADER).
- Protocol fixes: TCP framing, iteration parsing, multicast filter,
  IP encoding and status in the DiscoveryMessage.
- Handshake and network errors handled without killing processes.
- Global Start/Stop/Restart/Close Functions buttons (Ctrl+W/E/R/Q),
  with parallel stop, Ctrl+C handling and crashed-process detection.
- Message editor fixed (validation, iterations, no duplicated sends) and
  windows without leaks, placed at configurable positions.
- Timeouts, ports and window positions in Constants.py; IGNORE_HANDSHAKE.

Pending: real FunctionCommand/FunctionResponse values and SCD format.