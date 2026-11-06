# Born_2_be_root - 11/10/2022

!# Just the Born_2_be_root :)

Documentacion - https://drive.google.com/drive/folders/1W3xtPNuVMlD9KfL1pCW4qMHRBYVVNFG8?usp=share_link


from MessageViewer import MessageViewer
from MessageDisplayer import MessageDisplayer


def create_message_viewer(master: tk.Misc, msgs_list: list[Message], displayer_name: str,
                          fid_names: callable = None, bd: int = 2) -> tk.Frame:
    """ The message viewer chosen with USE_NEW_MSG_VIEWER (both have process_data() and history())"""
    if USE_NEW_MSG_VIEWER:
        return MessageViewer(master, msgs_list=msgs_list, displayer_name=displayer_name, fid_names=fid_names, bd=bd)
    return MessageDisplayer(master, msgs_list=msgs_list, displayer_name=displayer_name, bd=bd)
