using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Net;
using System.Net.NetworkInformation;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;
using System.Windows.Forms;
using Microsoft.Win32.SafeHandles;

internal static class Launcher
{
    private static readonly object LogLock = new object();
    private static StreamWriter logWriter;
    private static string logPath;
    private static volatile bool serviceAnnouncedReady;

    [STAThread]
    private static int Main(string[] args)
    {
        bool checkOnly = args.Length == 1 && args[0] == "--check";
        bool ownsMutex = false;
        Process backend = null;
        Process app = null;
        ChildProcessJob job = null;
        StartupForm progress = null;

        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);

        using (Mutex mutex = new Mutex(false, LauncherMutexName()))
        {
            try
            {
                try { ownsMutex = mutex.WaitOne(0, false); }
                catch (AbandonedMutexException) { ownsMutex = true; }
                if (!ownsMutex)
                {
                    if (!checkOnly)
                        MessageBox.Show("이 폴더의 SafeHub가 이미 실행 중입니다. 열린 SafeHub 창을 확인해 주세요.",
                            "SafeHub", MessageBoxButtons.OK, MessageBoxIcon.Information);
                    return 2;
                }

                OpenLog();
                if (args.Length > 0 && !checkOnly)
                    throw new InvalidOperationException("지원하지 않는 실행 옵션입니다. 실행 아이콘을 다시 눌러 주세요.");

                Config config = Config.Read(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "config.json"));
                Log(config.RealOnly ? "실제 장비 연결 모드" : "장비 연결 전 체험 모드");
                AssertPortAvailable(config.Port);
                if (checkOnly)
                {
                    Log("설정 파일, 필요한 파일 및 포트 검사 통과. 프로세스는 시작하지 않았습니다.");
                    return 0;
                }

                Directory.CreateDirectory(config.DataDir);
                progress = new StartupForm(config.RealOnly);
                progress.Show();
                Application.DoEvents();
                job = new ChildProcessJob();
                backend = StartBackend(config);
                job.Add(backend);
                Log("직접 시작한 CSI 서비스 PID=" + backend.Id);
                WaitForService(config.Port, backend, progress, config.StartupTimeoutSeconds);
                if (progress.CancelRequested) throw new OperationCanceledException();

                app = Process.Start(AppStartInfo(config));
                if (app == null) throw new InvalidOperationException("SafeHub 화면을 시작하지 못했습니다.");
                job.Add(app);
                Log("직접 시작한 SafeHub 앱 PID=" + app.Id);
                progress.Complete();

                while (!app.WaitForExit(250))
                {
                    if (backend.HasExited)
                        throw new InvalidOperationException("와이파이 센싱 서비스가 종료되었습니다. SafeHub를 다시 실행해 주세요.");
                }
                if (app.ExitCode != 0)
                    throw new InvalidOperationException("SafeHub 화면이 예기치 않게 종료되었습니다. 다시 실행해 주세요. (코드 " + app.ExitCode + ")");
                Log("SafeHub 창 종료. 이 실행에서 시작한 서비스만 정리합니다.");
                return 0;
            }
            catch (OperationCanceledException)
            {
                Log("사용자가 시작을 취소했습니다.");
                return 130;
            }
            catch (Exception error)
            {
                Log(error.ToString());
                if (progress != null) progress.Complete();
                if (!checkOnly)
                    MessageBox.Show(error.Message + "\n\n" +
                        (String.IsNullOrEmpty(logPath) ? "실행 폴더에 쓸 수 있는지 확인해 주세요." : "확인용 기록: " + logPath),
                        "SafeHub 실행 확인", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return 1;
            }
            finally
            {
                if (progress != null) progress.Dispose();
                // Closing this private job terminates only its assigned children.
                if (job != null) job.Dispose();
                StopOwnedProcess(app);
                StopOwnedProcess(backend);
                Log("런처 종료");
                lock (LogLock)
                {
                    if (logWriter != null) logWriter.Dispose();
                    logWriter = null;
                }
                if (ownsMutex) mutex.ReleaseMutex();
            }
        }
    }

    private static void OpenLog()
    {
        string directory = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "logs");
        Directory.CreateDirectory(directory);
        logPath = Path.Combine(directory, "launcher-" + DateTime.Now.ToString("yyyyMMdd-HHmmss") +
            "-" + Process.GetCurrentProcess().Id + ".log");
        logWriter = new StreamWriter(logPath, false, new UTF8Encoding(false));
        logWriter.AutoFlush = true;
        Log("SafeHub 실행 준비");
    }

    private static string LauncherMutexName()
    {
        // Separate installations may run together when they use different ports.
        string directory = Path.GetFullPath(AppDomain.CurrentDomain.BaseDirectory)
            .TrimEnd(Path.DirectorySeparatorChar).ToUpperInvariant();
        using (SHA256 hash = SHA256.Create())
            return "Local\\SafeHubLauncher_" +
                BitConverter.ToString(hash.ComputeHash(Encoding.UTF8.GetBytes(directory))).Replace("-", "");
    }

    private static ProcessStartInfo AppStartInfo(Config config)
    {
        ProcessStartInfo info = new ProcessStartInfo
        {
            FileName = config.AppExe,
            WorkingDirectory = Path.GetDirectoryName(config.AppExe),
            UseShellExecute = false,
            CreateNoWindow = false
        };
        if (!String.IsNullOrEmpty(config.SettingsFile))
            info.EnvironmentVariables["SAFEHUB_CONFIG_FILE"] = config.SettingsFile;
        return info;
    }

    private static void Log(string message)
    {
        lock (LogLock)
        {
            if (logWriter == null) return;
            try { logWriter.WriteLine(DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss.fff") + " " + message); }
            catch (IOException) { }
        }
    }

    private static void AssertPortAvailable(int port)
    {
        foreach (IPEndPoint endpoint in IPGlobalProperties.GetIPGlobalProperties().GetActiveTcpListeners())
        {
            if (endpoint.Port == port)
                throw new InvalidOperationException("통신 포트 " + port + "번을 다른 프로그램이 사용 중입니다.\n" +
                    "기존 SafeHub 또는 센싱 서비스를 직접 닫은 뒤 다시 실행해 주세요. 다른 프로그램은 종료하지 않았습니다.");
        }
    }

    private static Process StartBackend(Config config)
    {
        Process process = new Process { StartInfo = BackendStartInfo(config) };
        process.OutputDataReceived += delegate(object sender, DataReceivedEventArgs e)
        {
            if (e.Data == null) return;
            if (e.Data == "SafeHub CSI ready: http://127.0.0.1:" + config.Port)
                serviceAnnouncedReady = true;
            Log("[CSI] " + e.Data);
        };
        process.ErrorDataReceived += delegate(object sender, DataReceivedEventArgs e)
        { if (e.Data != null) Log("[CSI 오류] " + e.Data); };
        try
        {
            if (!process.Start()) throw new InvalidOperationException("와이파이 센싱 서비스를 시작하지 못했습니다.");
            process.BeginOutputReadLine();
            process.BeginErrorReadLine();
            return process;
        }
        catch { StopOwnedProcess(process); throw; }
    }

    private static ProcessStartInfo BackendStartInfo(Config config)
    {
        ProcessStartInfo info = new ProcessStartInfo
        {
            FileName = config.PythonExe,
            Arguments = (config.IsolatedPython ? "-I " : "") + "-X utf8 -u " + Quote(config.BridgeScript) + " --port " + config.Port +
                " --allow-training --data-dir " + Quote(config.DataDir) +
                (config.RealOnly ? " --real-only" : ""),
            WorkingDirectory = Path.GetDirectoryName(config.BridgeScript),
            UseShellExecute = false,
            CreateNoWindow = true,
            WindowStyle = ProcessWindowStyle.Hidden,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            StandardOutputEncoding = Encoding.UTF8,
            StandardErrorEncoding = Encoding.UTF8
        };
        info.EnvironmentVariables["PYTHONPATH"] = config.PythonSitePackages;
        info.EnvironmentVariables["PYTHONUTF8"] = "1";
        info.EnvironmentVariables["PYTHONIOENCODING"] = "utf-8";
        info.EnvironmentVariables["PYTHONNOUSERSITE"] = "1";
        return info;
    }

    private static void WaitForService(int port, Process backend, StartupForm progress, int timeoutSeconds)
    {
        Stopwatch elapsed = Stopwatch.StartNew();
        while (elapsed.Elapsed < TimeSpan.FromSeconds(timeoutSeconds))
        {
            Application.DoEvents();
            if (progress.CancelRequested) throw new OperationCanceledException();
            if (backend.HasExited)
                throw new InvalidOperationException("와이파이 센싱 서비스가 준비 중 종료되었습니다. 실행 기록을 확인해 주세요.");
            // A port-check race must never connect the UI to somebody else's service.
            if (serviceAnnouncedReady && ServiceReady(port))
            {
                if (backend.HasExited)
                    throw new InvalidOperationException("와이파이 센싱 서비스가 종료되었습니다.");
                Log("CSI /state 준비 확인 (" + elapsed.Elapsed.TotalSeconds.ToString("F1") + "초)");
                return;
            }
            progress.SetElapsed((int)elapsed.Elapsed.TotalSeconds);
            Thread.Sleep(200);
        }
        throw new InvalidOperationException(timeoutSeconds + "초 동안 와이파이 센싱 서비스를 준비하지 못했습니다.\n" +
            "잠시 후 다시 실행해 주세요. 계속되지 않으면 실행 기록을 확인해 주세요.");
    }

    private static bool ServiceReady(int port)
    {
        try
        {
            HttpWebRequest request = (HttpWebRequest)WebRequest.Create("http://127.0.0.1:" + port + "/state");
            request.Proxy = null;
            request.Timeout = 800;
            request.ReadWriteTimeout = 800;
            request.KeepAlive = false;
            using (HttpWebResponse response = (HttpWebResponse)request.GetResponse())
            using (StreamReader reader = new StreamReader(response.GetResponseStream(), Encoding.UTF8))
            {
                if (response.StatusCode != HttpStatusCode.OK) return false;
                Dictionary<string, object> state = new JavaScriptSerializer().Deserialize<Dictionary<string, object>>(reader.ReadToEnd());
                return state != null && state.ContainsKey("mode") && state.ContainsKey("recognition");
            }
        }
        catch (WebException) { return false; }
        catch (IOException) { return false; }
        catch (ArgumentException) { return false; }
        catch (InvalidOperationException) { return false; }
    }

    // Windows command-line escaping; spaces, quotes and trailing slashes are preserved.
    private static string Quote(string value)
    {
        StringBuilder result = new StringBuilder("\"");
        int slashes = 0;
        foreach (char character in value)
        {
            if (character == '\\') { slashes++; continue; }
            if (character == '"')
            {
                result.Append('\\', slashes * 2 + 1);
                result.Append('"');
            }
            else
            {
                result.Append('\\', slashes);
                result.Append(character);
            }
            slashes = 0;
        }
        result.Append('\\', slashes * 2);
        result.Append('"');
        return result.ToString();
    }

    private static void StopOwnedProcess(Process process)
    {
        if (process == null) return;
        try
        {
            if (!process.HasExited) process.Kill();
            process.WaitForExit(2500);
        }
        catch (InvalidOperationException) { }
        catch (Win32Exception error) { Log("시작한 프로세스 정리 확인: " + error.Message); }
        finally { process.Dispose(); }
    }

    private sealed class Config
    {
        internal string PythonExe, PythonSitePackages, BridgeScript, DataDir, AppExe, SettingsFile;
        internal int Port, StartupTimeoutSeconds;
        internal bool RealOnly, IsolatedPython;

        internal static Config Read(string path)
        {
            if (!File.Exists(path))
                throw new InvalidOperationException("실행 설정 파일(config.json)이 없습니다. 실행 폴더 전체를 확인해 주세요.");
            Dictionary<string, object> values;
            try { values = new JavaScriptSerializer().Deserialize<Dictionary<string, object>>(File.ReadAllText(path, Encoding.UTF8)); }
            catch (Exception error) { throw new InvalidOperationException("config.json 형식이 올바르지 않습니다.", error); }
            if (values == null) throw new InvalidOperationException("config.json 설정이 비어 있습니다.");
            Config config = new Config
            {
                PythonExe = ReadPath(values, "python_exe", false),
                PythonSitePackages = ReadPath(values, "python_site_packages", true),
                BridgeScript = ReadPath(values, "bridge_script", false),
                DataDir = ReadPath(values, "data_dir", null),
                AppExe = ReadPath(values, "app_exe", false),
                Port = 8765,
                StartupTimeoutSeconds = 45
            };
            if (values.ContainsKey("port") &&
                (!Int32.TryParse(Convert.ToString(values["port"]), out config.Port) || config.Port < 1 || config.Port > 65535))
                throw new InvalidOperationException("config.json의 port는 1~65535 사이 정수여야 합니다.");
            if (values.ContainsKey("real_only"))
            {
                if (!(values["real_only"] is bool))
                    throw new InvalidOperationException("config.json의 real_only는 true 또는 false여야 합니다.");
                config.RealOnly = (bool)values["real_only"];
            }
            if (values.ContainsKey("isolated_python"))
            {
                if (!(values["isolated_python"] is bool))
                    throw new InvalidOperationException("isolated_python은 true 또는 false여야 합니다.");
                config.IsolatedPython = (bool)values["isolated_python"];
            }
            if (values.ContainsKey("startup_timeout_seconds") &&
                (!Int32.TryParse(Convert.ToString(values["startup_timeout_seconds"]), out config.StartupTimeoutSeconds)
                 || config.StartupTimeoutSeconds < 15 || config.StartupTimeoutSeconds > 300))
                throw new InvalidOperationException("startup_timeout_seconds는 15~300 사이 정수여야 합니다.");
            if (values.ContainsKey("settings_file"))
                config.SettingsFile = ReadPath(values, "settings_file", false);
            return config;
        }

        private static string ReadPath(Dictionary<string, object> values, string key, bool? directory)
        {
            object raw;
            if (!values.TryGetValue(key, out raw) || !(raw is string) || String.IsNullOrWhiteSpace((string)raw))
                throw new InvalidOperationException("config.json에 " + key + " 경로가 필요합니다.");
            string path = (string)raw;
            if (!Path.IsPathRooted(path))
                path = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, path);
            path = Path.GetFullPath(path);
            if (directory == true && !Directory.Exists(path))
                throw new InvalidOperationException("필요한 폴더가 없습니다: " + key + "\n" + path);
            if (directory == false && !File.Exists(path))
                throw new InvalidOperationException("필요한 파일이 없습니다: " + key + "\n" + path);
            return path;
        }
    }

    private sealed class StartupForm : Form
    {
        private readonly Label message;
        private readonly bool realOnly;
        private bool completing;
        internal bool CancelRequested { get; private set; }

        internal StartupForm(bool realOnly)
        {
            this.realOnly = realOnly;
            Text = "SafeHub 준비 중";
            ClientSize = new Size(450, 135);
            FormBorderStyle = FormBorderStyle.FixedDialog;
            StartPosition = FormStartPosition.CenterScreen;
            MaximizeBox = false;
            MinimizeBox = false;
            Font = new Font("맑은 고딕", 10);
            message = new Label { Dock = DockStyle.Fill, TextAlign = ContentAlignment.MiddleCenter };
            Controls.Add(message);
            SetElapsed(0);
            FormClosing += delegate { if (!completing) CancelRequested = true; };
        }

        internal void SetElapsed(int seconds)
        {
            message.Text = realOnly
                ? "SafeHub 실제 장비 연결 모드를 준비하고 있습니다.\n와이파이 센싱 서비스 시작 중 · " + seconds + "초\n\n장비가 연결되면 실제 신호를 수집할 수 있습니다."
                : "SafeHub 통합 체험을 준비하고 있습니다.\n와이파이 센싱 서비스 시작 중 · " + seconds + "초\n\n장비 없이도 화면과 모의 신호를 체험할 수 있습니다.";
        }

        internal void Complete() { completing = true; Close(); }
    }

    private sealed class ChildProcessJob : IDisposable
    {
        private readonly SafeJobHandle handle;

        internal ChildProcessJob()
        {
            handle = CreateJobObject(IntPtr.Zero, null);
            if (handle.IsInvalid) throw new Win32Exception(Marshal.GetLastWin32Error(), "실행 프로세스 보호를 준비하지 못했습니다.");
            JobExtendedLimitInformation limits = new JobExtendedLimitInformation();
            limits.BasicLimitInformation.LimitFlags = 0x2000; // JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
            int size = Marshal.SizeOf(typeof(JobExtendedLimitInformation));
            IntPtr buffer = Marshal.AllocHGlobal(size);
            try
            {
                Marshal.StructureToPtr(limits, buffer, false);
                if (!SetInformationJobObject(handle, 9, buffer, (uint)size))
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "실행 프로세스 정리 설정에 실패했습니다.");
            }
            catch { handle.Dispose(); throw; }
            finally { Marshal.FreeHGlobal(buffer); }
        }

        internal void Add(Process process)
        {
            if (!AssignProcessToJobObject(handle, process.Handle))
                throw new Win32Exception(Marshal.GetLastWin32Error(), "시작한 프로세스의 안전한 종료를 설정하지 못했습니다.");
        }
        public void Dispose() { handle.Dispose(); }
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct JobBasicLimitInformation
    {
        public long PerProcessUserTimeLimit, PerJobUserTimeLimit;
        public uint LimitFlags;
        public UIntPtr MinimumWorkingSetSize, MaximumWorkingSetSize;
        public uint ActiveProcessLimit;
        public UIntPtr Affinity;
        public uint PriorityClass, SchedulingClass;
    }
    [StructLayout(LayoutKind.Sequential)]
    private struct IoCounters
    {
        public ulong ReadOperationCount, WriteOperationCount, OtherOperationCount;
        public ulong ReadTransferCount, WriteTransferCount, OtherTransferCount;
    }
    [StructLayout(LayoutKind.Sequential)]
    private struct JobExtendedLimitInformation
    {
        public JobBasicLimitInformation BasicLimitInformation;
        public IoCounters IoInfo;
        public UIntPtr ProcessMemoryLimit, JobMemoryLimit, PeakProcessMemoryUsed, PeakJobMemoryUsed;
    }
    private sealed class SafeJobHandle : SafeHandleZeroOrMinusOneIsInvalid
    {
        private SafeJobHandle() : base(true) { }
        protected override bool ReleaseHandle() { return CloseHandle(handle); }
    }
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern SafeJobHandle CreateJobObject(IntPtr attributes, string name);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool SetInformationJobObject(SafeJobHandle job, int informationClass, IntPtr information, uint length);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool AssignProcessToJobObject(SafeJobHandle job, IntPtr process);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool CloseHandle(IntPtr handle);
}
