using System;
using System.IO;
using System.Reflection;
using System.Web.Script.Serialization;
using System.Collections.Generic;

internal static class TestLauncherConfig
{
    private static int Main(string[] args)
    {
        Type launcher = Assembly.LoadFrom(args[0]).GetType("Launcher");
        Type config = launcher.GetNestedType("Config", BindingFlags.NonPublic);
        MethodInfo read = config.GetMethod("Read", BindingFlags.Static | BindingFlags.NonPublic);
        string root = AppDomain.CurrentDomain.BaseDirectory;
        File.WriteAllText(Path.Combine(root, "fixture.dat"), "fixture");
        Directory.CreateDirectory(Path.Combine(root, "modules"));
        var values = new Dictionary<string, object> {
            { "python_exe", "fixture.dat" }, { "python_site_packages", "modules" },
            { "bridge_script", "fixture.dat" }, { "app_exe", "fixture.dat" },
            { "data_dir", "새 기록 폴더" }, { "real_only", true }, { "port", 18768 }
        };
        string path = Path.Combine(root, "fixture.json");
        var serializer = new JavaScriptSerializer();
        File.WriteAllText(path, serializer.Serialize(values));
        object loaded = read.Invoke(null, new object[] { path });
        Assert((string)Field(config, loaded, "PythonExe") == Path.Combine(root, "fixture.dat"));
        Assert((string)Field(config, loaded, "DataDir") == Path.Combine(root, "새 기록 폴더"));
        Assert((int)Field(config, loaded, "StartupTimeoutSeconds") == 45);
        values["startup_timeout_seconds"] = 180;
        File.WriteAllText(path, serializer.Serialize(values));
        loaded = read.Invoke(null, new object[] { path });
        Assert((int)Field(config, loaded, "StartupTimeoutSeconds") == 180);
        MethodInfo start = launcher.GetMethod("BackendStartInfo", BindingFlags.Static | BindingFlags.NonPublic);
        var info = (System.Diagnostics.ProcessStartInfo)start.Invoke(null, new object[] { loaded });
        Assert(info.Arguments.StartsWith("-X utf8 -u "));
        values["isolated_python"] = true;
        File.WriteAllText(path, serializer.Serialize(values));
        loaded = read.Invoke(null, new object[] { path });
        info = (System.Diagnostics.ProcessStartInfo)start.Invoke(null, new object[] { loaded });
        Assert(info.Arguments.StartsWith("-I -X utf8 -u "));
        values["isolated_python"] = "true";
        File.WriteAllText(path, serializer.Serialize(values));
        bool invalidIsolationRejected = false;
        try { read.Invoke(null, new object[] { path }); }
        catch (TargetInvocationException error) { invalidIsolationRejected = error.InnerException is InvalidOperationException; }
        Assert(invalidIsolationRejected);
        values["isolated_python"] = true;
        foreach (object invalid in new object[] { 0, 301, true, "bad" })
        {
            values["startup_timeout_seconds"] = invalid;
            File.WriteAllText(path, serializer.Serialize(values));
            bool rejected = false;
            try { read.Invoke(null, new object[] { path }); }
            catch (TargetInvocationException error) { rejected = error.InnerException is InvalidOperationException; }
            Assert(rejected);
        }
        Console.WriteLine("PASS: relative paths independent of cwd, fresh data path, default/portable timeout, invalid timeout rejection");
        return 0;
    }

    private static object Field(Type type, object instance, string name)
    {
        return type.GetField(name, BindingFlags.Instance | BindingFlags.NonPublic).GetValue(instance);
    }

    private static void Assert(bool condition)
    {
        if (!condition) throw new InvalidOperationException("Launcher config assertion failed.");
    }
}
