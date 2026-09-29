using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;

namespace CodexClipboard {
    public sealed class HotkeyWindow : NativeWindow, IDisposable {
        public event EventHandler Invoked;
        public HotkeyWindow() {
            CreateHandle(new CreateParams { Caption = "CodexClipboardBridge", Parent = new IntPtr(-3) });
            if (!RegisterHotKey(Handle, 1, 0x4003, 0x56)) {
                int error = Marshal.GetLastWin32Error();
                DestroyHandle();
                throw new Win32Exception(error, "Ctrl+Alt+V is already in use.");
            }
        }
        protected override void WndProc(ref Message message) {
            if (message.Msg == 0x0312 && Invoked != null) Invoked(this, EventArgs.Empty);
            base.WndProc(ref message);
        }
        public void Dispose() {
            if (Handle != IntPtr.Zero) { UnregisterHotKey(Handle, 1); DestroyHandle(); }
        }
        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool RegisterHotKey(IntPtr window, int id, uint modifiers, uint key);
        [DllImport("user32.dll")]
        private static extern bool UnregisterHotKey(IntPtr window, int id);
    }

    public static class TerminalInput {
        [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")] public static extern uint GetClipboardSequenceNumber();
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetWindowText(IntPtr window, StringBuilder text, int max);
        [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);
        [DllImport("user32.dll")] private static extern short GetAsyncKeyState(int key);
        [DllImport("user32.dll", SetLastError = true)] private static extern uint SendInput(uint count, INPUT[] inputs, int size);
        public static uint ProcessId(IntPtr window) { uint id; GetWindowThreadProcessId(window, out id); return id; }
        public static string Title(IntPtr window) { var text = new StringBuilder(1024); GetWindowText(window, text, text.Capacity); return text.ToString(); }
        public static bool ModifiersDown() {
            return (GetAsyncKeyState(0x11) & 0x8000) != 0 || (GetAsyncKeyState(0x12) & 0x8000) != 0 || (GetAsyncKeyState(0x10) & 0x8000) != 0;
        }
        public static bool Paste(IntPtr expectedWindow) {
            if (GetForegroundWindow() != expectedWindow || ModifiersDown()) return false;
            INPUT[] keys = { Key(0x11, false), Key(0x10, false), Key(0x56, false), Key(0x56, true), Key(0x10, true), Key(0x11, true) };
            if (SendInput((uint)keys.Length, keys, Marshal.SizeOf(typeof(INPUT))) != keys.Length)
                throw new Win32Exception(Marshal.GetLastWin32Error(), "Could not paste; use Ctrl+Shift+V manually.");
            return true;
        }
        private static INPUT Key(ushort code, bool up) {
            INPUT result = new INPUT(); result.type = 1; result.data.keyboard.wVk = code;
            result.data.keyboard.dwFlags = up ? 2U : 0U; return result;
        }
        [StructLayout(LayoutKind.Sequential)] private struct INPUT { public uint type; public UNION data; }
        [StructLayout(LayoutKind.Explicit)] private struct UNION {
            [FieldOffset(0)] public KEYBOARD keyboard;
            [FieldOffset(0)] public MOUSE mouse;
        }
        [StructLayout(LayoutKind.Sequential)] private struct KEYBOARD {
            public ushort wVk, wScan; public uint dwFlags, time; public UIntPtr extra;
        }
        [StructLayout(LayoutKind.Sequential)] private struct MOUSE {
            public int dx, dy; public uint mouseData, dwFlags, time; public UIntPtr extra;
        }
    }
}
