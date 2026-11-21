#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <string>

#include "flutter_window.h"
#include "utils.h"

namespace {

// The app asks Windows to run itself as administrator with this first, and
// the rest of the command line is PowerShell's. It used to ask for
// powershell.exe directly, and the permission prompt said "Windows
// PowerShell" with PowerShell's icon; this way it says Nebula VPN.
constexpr wchar_t kElevatedStep[] = L"--nebula-elevated ";

// Runs one PowerShell step hidden, waits for it, and returns its exit code.
// PowerShell by its full System32 path: an elevated process must not find
// its program through a search order someone else could put a file into.
int RunElevatedStep(const wchar_t* powershell_arguments) {
  wchar_t system_dir[MAX_PATH];
  const UINT length = ::GetSystemDirectoryW(system_dir, MAX_PATH);
  if (length == 0 || length >= MAX_PATH) {
    return 1;
  }
  const std::wstring powershell =
      std::wstring(system_dir) + L"\\WindowsPowerShell\\v1.0\\powershell.exe";
  std::wstring command =
      L"\"" + powershell + L"\" " + std::wstring(powershell_arguments);

  STARTUPINFOW startup{};
  startup.cb = sizeof(startup);
  PROCESS_INFORMATION process{};
  // Out of the app's job (see wWinMain). Windows puts this elevated process
  // in it, as the child of the app that asked for it, and closing the job
  // ended the helper mid-session: its DNS rule and kill switch stayed, and
  // the PC had no internet after Exit until a reset.
  // Outside, the helper sees the app gone and undoes them, as it was built
  // to. Where breaking away is refused, it starts as before.
  if (!::CreateProcessW(powershell.c_str(), command.data(), nullptr, nullptr,
                        FALSE, CREATE_NO_WINDOW | CREATE_BREAKAWAY_FROM_JOB,
                        nullptr, nullptr, &startup, &process) &&
      !::CreateProcessW(powershell.c_str(), command.data(), nullptr, nullptr,
                        FALSE, CREATE_NO_WINDOW, nullptr, nullptr, &startup,
                        &process)) {
    return 1;
  }
  ::WaitForSingleObject(process.hProcess, INFINITE);
  DWORD exit_code = 1;
  ::GetExitCodeProcess(process.hProcess, &exit_code);
  ::CloseHandle(process.hThread);
  ::CloseHandle(process.hProcess);
  return static_cast<int>(exit_code);
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Before anything else: in this mode the app is only a named, elevated
  // launcher for one step, and never shows a window.
  if (command_line != nullptr &&
      ::wcsncmp(command_line, kElevatedStep, ::wcslen(kElevatedStep)) == 0) {
    return RunElevatedStep(command_line + ::wcslen(kElevatedStep));
  }

  // One app at a time. Launching it again -- from the Start menu, a
  // shortcut, or sign-in while it already sits in the tray -- brings the
  // running window forward instead of adding another tray icon and a second
  // owner for the same tunnel. Access denied means the running one is
  // elevated and holds the name: still running.
  HANDLE single_instance =
      ::CreateMutexW(nullptr, FALSE, L"Local\\NebulaVPN.SingleInstance");
  const DWORD mutex_error = ::GetLastError();
  if (single_instance == nullptr ? mutex_error == ERROR_ACCESS_DENIED
                                 : mutex_error == ERROR_ALREADY_EXISTS) {
    HWND running = ::FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", L"Nebula VPN");
    if (running != nullptr) {
      ::ShowWindow(running, ::IsIconic(running) ? SW_RESTORE : SW_SHOW);
      ::SetForegroundWindow(running);
      // Repainted by the running app on WM_SHOWWINDOW; this covers a window
      // that was visible already but never drew.
      ::RedrawWindow(running, nullptr, nullptr,
                     RDW_INVALIDATE | RDW_ALLCHILDREN | RDW_UPDATENOW);
    }
    if (single_instance != nullptr) {
      ::CloseHandle(single_instance);
    }
    return EXIT_SUCCESS;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  // Every engine the app starts (the DNS tunnel, proxy-mode Xray and
  // Hysteria, Aether) is a process of its own. Stopping them is the app's
  // job, which a crash, an End task or a power cut skips: a DNS tunnel
  // engine was found still running three days on. In a
  // job that ends its processes when it closes, Windows stops them however
  // the app ends. The handle is never closed by hand; the app's exit closes
  // it. The elevated VPN helper lands in it too -- Windows starts it as this
  // app's child -- so it is allowed to break away, and does (RunElevatedStep):
  // it has a DNS rule and a kill switch to undo when the app is gone.
  if (HANDLE job = ::CreateJobObjectW(nullptr, nullptr)) {
    JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits{};
    limits.BasicLimitInformation.LimitFlags =
        JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE | JOB_OBJECT_LIMIT_BREAKAWAY_OK;
    if (!::SetInformationJobObject(job, JobObjectExtendedLimitInformation,
                                   &limits, sizeof(limits)) ||
        !::AssignProcessToJobObject(job, ::GetCurrentProcess())) {
      ::CloseHandle(job);
    }
  }

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(420, 720);
  if (!window.Create(L"Nebula VPN", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
