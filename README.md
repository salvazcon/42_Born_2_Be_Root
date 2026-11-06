# Born_2_be_root - 11/10/2022

!# Just the Born_2_be_root :)

Documentacion - https://drive.google.com/drive/folders/1W3xtPNuVMlD9KfL1pCW4qMHRBYVVNFG8?usp=share_link



    def _build_controls(self, master: tk.Misc):
        # same layout as the old viewer: filters on the left, buttons on the right, in two rows
        frame = tk.Frame(master)
        frame.grid(row=2, column=0, sticky="ew", padx=5, pady=(5, 10))

        tk.Label(frame, text="Filter by Msg:", anchor="center").grid(row=0, column=0, sticky="nsew", padx=(5, 5))
        MultiSelectDropdown(
            frame, MSG_NAME_FILTER_VALUES, must_have_one=True, show_limit=0, width=1, start_checked=True,
            on_select=lambda e: self._apply_filter(e, is_msg_name_filter=True)
        ).grid(row=0, column=1, sticky="nsew", padx=(0, 30), pady=5)
        ttk.Button(frame, text="Delete all", width=20, command=self._delete_msgs).grid(
            row=0, column=2, sticky="nsew", padx=5, pady=5)

        tk.Label(frame, text="Filter by FID:", anchor="center").grid(row=1, column=0, sticky="nsew", padx=(5, 5))
        self._fid_filter = MultiSelectDropdown(
            frame, [], must_have_one=True, show_limit=0, width=1, start_checked=True,
            on_select=lambda e: self._apply_filter(e, is_msg_name_filter=False)
        )
        self._fid_filter.grid(row=1, column=1, sticky="nsew", padx=(0, 30), pady=5)
        self._button_pause = ttk.Button(frame, text="Pause", width=20, command=self._toggle_pause)
        self._button_pause.grid(row=1, column=2, sticky="nsew", padx=5, pady=5)

        # fixed width (the widest text): the window must not grow when the counter gains a digit
        self._counter = tk.Label(frame, text="", anchor="e", width=len(f"{MAX_HISTORY} msgs"))
        self._counter.grid(row=0, column=3, rowspan=2, sticky="e", padx=(10, 5))
        frame.columnconfigure(3, weight=1)
