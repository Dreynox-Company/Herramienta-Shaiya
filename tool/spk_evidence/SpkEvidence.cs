// Standalone .NET Framework transport utility. This is NOT a decryptor.
// It reads only an explicitly selected SPK and optional profile/game executable.
// No networking, process launch, registry change, administrator rights or SDK.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Web.Script.Serialization;
using System.Windows.Forms;

namespace ShStudio.SpkEvidence {
  public sealed class CaptureRange {
    public long offset { get; set; }
    public int length { get; set; }
    public string purpose { get; set; }
  }
  public sealed class CapturePlan {
    public int schema { get; set; }
    public long fileBytes { get; set; }
    public string headerSha256 { get; set; }
    public string indexSha256 { get; set; }
    public CaptureRange[] ranges { get; set; }
  }
  public static class Program {
    const int MaxIndex = 64 * 1024 * 1024;
    const int MaxCapture = 32 * 1024 * 1024;
    const int MaxRange = 8 * 1024 * 1024;
    static readonly JavaScriptSerializer Json = new JavaScriptSerializer {
      MaxJsonLength = 4 * 1024 * 1024, RecursionLimit = 32
    };
    static readonly Encoding Utf8 = new UTF8Encoding(false, true);
    static readonly string Caption = "ShStudio - evidencia SPK real";
    static void Need(bool condition, string message) {
      if (!condition) throw new InvalidDataException(message);
    }
    static string Hash(byte[] bytes) {
      using (var sha = SHA256.Create()) return BitConverter.ToString(sha.ComputeHash(bytes)).Replace("-", "").ToLowerInvariant();
    }
    static long U64(byte[] bytes, int at) { return checked((long)BitConverter.ToUInt64(bytes, at)); }
    static long U32(byte[] bytes, int at) { return BitConverter.ToUInt32(bytes, at); }
    static bool Same(string a, string b) { return String.Equals(a, b, StringComparison.OrdinalIgnoreCase); }
    static byte[] Read(FileStream source, long offset, int count) {
      Need(offset >= 0 && count >= 0 && offset <= source.Length && count <= source.Length - offset,
        "Rango fuera del SPK. No se completara la captura.");
      var bytes = new byte[count]; source.Position = offset; int done = 0;
      while (done < count) {
        int n = source.Read(bytes, done, count - done);
        if (n == 0) throw new EndOfStreamException("Lectura incompleta.");
        done += n;
      }
      return bytes;
    }
    static byte[] SmallFile(string path, int maximum) {
      using (var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read)) {
        Need(stream.Length > 0 && stream.Length <= maximum, "Archivo auxiliar vacio o demasiado grande.");
        return Read(stream, 0, checked((int)stream.Length));
      }
    }
    static void Put(ZipArchive zip, string name, byte[] bytes, List<object> entries, long? offset) {
      var item = zip.CreateEntry(name, CompressionLevel.Optimal);
      using (var target = item.Open()) target.Write(bytes, 0, bytes.Length);
      entries.Add(new { file = name, bytes = bytes.Length, sha256 = Hash(bytes), sourceOffset = offset });
    }
    static bool HasResourceKey(Dictionary<string, object> profile) {
      object key;
      if (profile.TryGetValue("resourceSecretHex", out key) && KeyShape(key)) return true;
      object resources;
      if (profile.TryGetValue("resources", out resources)) {
        var map = resources as Dictionary<string, object>;
        if (map != null && map.TryGetValue("secretHex", out key) && KeyShape(key)) return true;
      }
      return false;
    }
    static bool KeyShape(object value) {
      var text = value as string;
      return text != null && (text.Length == 32 || text.Length == 64) && text.All(Uri.IsHexDigit);
    }
    public static void Capture(string spk, string planPath, string output, string profile, string game) {
      var planBytes = SmallFile(planPath, 2 * 1024 * 1024);
      var plan = Json.Deserialize<CapturePlan>(Utf8.GetString(planBytes));
      Need(plan != null && plan.schema == 1 && plan.ranges != null && plan.ranges.Length <= 4096,
        "Plan de captura invalido.");
      Need(!File.Exists(output), "El destino ya existe. Elige otro nombre; no se sobrescribe.");
      foreach (var input in new[] { spk, planPath, profile, game })
        if (!String.IsNullOrEmpty(input)) Need(!Same(Path.GetFullPath(input), Path.GetFullPath(output)), "El destino no puede ser un archivo de origen.");
      string temporary = Path.GetFullPath(output) + ".partial-" + Guid.NewGuid().ToString("N");
      bool temporaryCreated = false;
      try {
        using (var source = new FileStream(spk, FileMode.Open, FileAccess.Read, FileShare.Read)) {
          Need(source.Length == plan.fileBytes && source.Length >= 192, "Tamano de SPK distinto del inventario. No se aplicara este plan.");
          var header = Read(source, 0, 128);
          Need(U32(header, 0) == 0x9e7bd34c && U32(header, 4) == 0x30000, "Firma o version SPK no compatible.");
          Need(Same(Hash(header), plan.headerSha256), "Cabecera distinta. El plan corresponde a otro SPK.");
          long indexOffset = U64(header, 8), indexBytes = U64(header, 16), decoded = U64(header, 24);
          long count = U32(header, 32), auxOffset = U64(header, 100), auxCount = U32(header, 108);
          Need(count > 0 && decoded == checked(count * 96) && decoded <= MaxIndex,
            "Geometria de indice no valida.");
          Need(auxOffset >= 128 && auxCount <= MaxIndex / 32 && indexOffset == checked(auxOffset + auxCount * 32),
            "Geometria auxiliar no valida.");
          Need(indexBytes > 0 && indexBytes <= MaxIndex && indexOffset <= source.Length - 64 &&
            indexBytes == source.Length - 64 - indexOffset, "Indice fuera del contenedor.");
          long total = 0, previousEnd = 128;
          var ranges = plan.ranges.OrderBy(r => r == null ? -1 : r.offset).ToArray();
          foreach (var range in ranges) {
            Need(range != null && range.length > 0 && range.length <= MaxRange && range.offset >= previousEnd &&
              range.offset <= auxOffset && range.length <= auxOffset - range.offset, "Rango solapado, fuera del payload o demasiado grande.");
            total = checked(total + range.length); previousEnd = checked(range.offset + range.length);
            Need(total <= MaxCapture, "La seleccion supera 32 MiB. No se capturara el contenedor completo.");
          }
          var encryptedIndex = Read(source, indexOffset, checked((int)indexBytes));
          Need(Same(Hash(encryptedIndex), plan.indexSha256), "El indice no coincide con el inventario. No se completara el paquete.");
          byte[] privateProfile = null, executable = null;
          if (!String.IsNullOrEmpty(profile)) {
            privateProfile = SmallFile(profile, 1024 * 1024);
            var rawProfile = Json.Deserialize<Dictionary<string, object>>(Utf8.GetString(privateProfile));
            Need(rawProfile != null && HasResourceKey(rawProfile), "El JSON seleccionado no contiene un perfil de recursos SPK reconocible. No selecciones un inventario ni una clave de otra aplicacion.");
            object boundIndex;
            if (rawProfile.TryGetValue("indexSha256", out boundIndex))
              Need(Same(Convert.ToString(boundIndex, CultureInfo.InvariantCulture), plan.indexSha256), "El perfil corresponde a otro indice SPK.");
          }
          if (!String.IsNullOrEmpty(game)) {
            executable = SmallFile(game, 64 * 1024 * 1024);
            Need(executable.Length >= 64 && executable[0] == 77 && executable[1] == 90, "El game.exe elegido no tiene cabecera MZ.");
            int pe = BitConverter.ToInt32(executable, 60);
            Need(pe >= 64 && pe <= executable.Length - 6 && executable[pe] == 80 && executable[pe+1] == 69 && executable[pe+2] == 0 && executable[pe+3] == 0,
              "El game.exe elegido no tiene cabecera PE valida.");
          }
          var entries = new List<object>();
          using (var file = new FileStream(temporary, FileMode.CreateNew, FileAccess.ReadWrite, FileShare.None)) {
            temporaryCreated = true;
            using (var zip = new ZipArchive(file, ZipArchiveMode.Create, true)) {
              Put(zip, "capture-plan.json", planBytes, entries, null);
              Put(zip, "ranges/header.bin", header, entries, 0);
              Put(zip, "ranges/encrypted-index.bin", encryptedIndex, entries, indexOffset);
              Put(zip, "ranges/auxiliary.bin", Read(source, auxOffset, checked((int)(auxCount * 32))), entries, auxOffset);
              Put(zip, "ranges/footer.bin", Read(source, source.Length - 64, 64), entries, source.Length - 64);
              for (int i = 0; i < ranges.Length; i++) {
                var range = ranges[i];
                Put(zip, "ranges/payload-" + i.ToString("D4") + ".bin", Read(source, range.offset, range.length), entries, range.offset);
                if (i % 25 == 0) Console.WriteLine("Capturando {0}/{1} rangos...", i + 1, ranges.Length);
              }
              if (privateProfile != null) Put(zip, "PRIVATE/resource-profile.json", privateProfile, entries, null);
              if (executable != null) Put(zip, "PRIVATE/game.exe", executable, entries, null);
              var manifest = new {
                schema = 1, kind = "shstudio-spk-real-evidence", createdUtc = DateTime.UtcNow.ToString("o"),
                sourceFileBytes = source.Length, headerSha256 = Hash(header), encryptedIndexSha256 = Hash(encryptedIndex),
                scope = "selected ciphertext ranges; NOT a complete SPK", fullDecryptionVerified = false,
                privateResourceProfileIncluded = privateProfile != null, nativeExecutableIncluded = executable != null,
                warning = "Contiene recursos y posiblemente una clave SPK privada. No publicar en GitHub. No se ha ejecutado el juego ni modificado el origen.",
                entries = entries.ToArray()
              };
              var item = zip.CreateEntry("manifest.json", CompressionLevel.Optimal);
              using (var target = item.Open()) {
                var bytes = Utf8.GetBytes(Json.Serialize(manifest)); target.Write(bytes, 0, bytes.Length);
              }
            }
            file.Flush(true);
          }
          // These checks detect replacements before publication. The open
          // Windows source handle disallows concurrent writes and deletion.
          Need(Same(Hash(Read(source, 0, 128)), plan.headerSha256) &&
            Same(Hash(Read(source, indexOffset, checked((int)indexBytes))), plan.indexSha256), "El origen cambio durante la captura.");
          using (var file = File.OpenRead(temporary)) using (var zip = new ZipArchive(file, ZipArchiveMode.Read)) {
            Need(zip.Entries.Count == entries.Count + 1, "Paquete incompleto.");
            foreach (var item in zip.Entries) using (var raw = item.Open()) raw.CopyTo(Stream.Null);
          }
          File.Move(temporary, output); temporaryCreated = false;
        }
      } finally {
        if (temporaryCreated && File.Exists(temporary)) File.Delete(temporary);
      }
    }
    static string Pick(string title, string filter, string initial, bool required) {
      using (var dialog = new OpenFileDialog { Title = title, Filter = filter, CheckFileExists = true, Multiselect = false,
        InitialDirectory = initial ?? "" }) {
        if (dialog.ShowDialog() == DialogResult.OK) return dialog.FileName;
        if (required) throw new OperationCanceledException("Operacion cancelada.");
        return null;
      }
    }
    static string AutoProfile(string folder) {
      foreach (var name in new[] { "data.spk.resources.json", "derived-resource-profile.json", "data.spk.profile.json" }) {
        var path = Path.Combine(folder, name);
        if (!File.Exists(path)) continue;
        try { if (HasResourceKey(Json.Deserialize<Dictionary<string, object>>(Utf8.GetString(SmallFile(path, 1024 * 1024))))) return path; }
        catch (Exception) { /* A broken candidate is not an accepted profile. */ }
      }
      return null;
    }
    static Dictionary<string, string> Arguments(string[] args) {
      var parsed = new Dictionary<string, string>();
      for (int i = 0; i < args.Length; i++) {
        Need(new[] { "--spk", "--plan", "--out", "--profile", "--game", "--allow-private" }.Contains(args[i]), "Argumento no reconocido.");
        if (args[i] == "--allow-private") { parsed.Add(args[i], "yes"); continue; }
        Need(i + 1 < args.Length, "Falta el valor de un argumento.");
        parsed.Add(args[i], args[++i]);
      }
      return parsed;
    }
    [STAThread]
    public static int Main(string[] args) {
      bool interactive = args.Length == 0;
      try {
        string spk, plan, output, profile = null, game = null;
        if (interactive) {
          Application.EnableVisualStyles();
          if (MessageBox.Show("Esta utilidad recopila muestras del SPK para terminar su analisis. NO afirma que este descifrado.\n\nNo modifica DATA.SPK, no ejecuta game.exe y no se conecta a Internet. El ZIP puede incluir el perfil de recursos (clave SPK privada) y el game.exe elegido. No lo publiques en un repositorio.\n\nContinuar?", Caption, MessageBoxButtons.YesNo, MessageBoxIcon.Information) != DialogResult.Yes) return 2;
          plan = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "capture-plan.json");
          spk = Pick("Selecciona el DATA.SPK real", "SPK|*.spk", null, true);
          var folder = Path.GetDirectoryName(spk); profile = AutoProfile(folder);
          if (profile == null) profile = Pick("Selecciona el perfil que ya lee recursos (Cancelar si no lo encuentras)", "Perfil SPK JSON|*.json", folder, false);
          game = Path.Combine(folder, "game.exe");
          if (!File.Exists(game)) game = Pick("game.exe de la misma instalacion (opcional)", "Ejecutable|*.exe", folder, false);
          if (profile == null && MessageBox.Show("No se encontro el perfil de recursos. La captura seguira siendo util, pero faltara la clave que ya funciona. Continuar sin ese perfil?", Caption, MessageBoxButtons.YesNo, MessageBoxIcon.Warning) != DialogResult.Yes) return 2;
          using (var dialog = new SaveFileDialog { Title = "Guardar paquete de evidencia", Filter = "ZIP|*.zip", FileName = "SPK-Evidencia-Real-" + DateTime.Now.ToString("yyyyMMdd-HHmmss") + ".zip", OverwritePrompt = true }) {
            if (dialog.ShowDialog() != DialogResult.OK) return 2; output = dialog.FileName;
          }
        } else {
          var a = Arguments(args);
          Need(a.ContainsKey("--spk") && a.ContainsKey("--plan") && a.ContainsKey("--out"), "Se requieren --spk, --plan y --out.");
          spk = a["--spk"]; plan = a["--plan"]; output = a["--out"];
          a.TryGetValue("--profile", out profile); a.TryGetValue("--game", out game);
          Need((profile == null && game == null) || a.ContainsKey("--allow-private"), "Confirma inclusion de datos privados con --allow-private.");
        }
        Capture(spk, plan, output, profile, game);
        Console.WriteLine("CAPTURA COMPLETA. No es una certificacion de descifrado.\n" + output);
        if (interactive) MessageBox.Show("Paquete creado:\n" + output + "\n\nCompartelo solo en el chat de trabajo. No lo publiques: puede contener la clave SPK. El archivo original no se modifico.", Caption);
        return 0;
      } catch (OperationCanceledException) { return 2; }
      catch (Exception error) {
        string message = "No se completo la captura: " + error.Message;
        Console.Error.WriteLine(message);
        if (interactive) MessageBox.Show(message, Caption, MessageBoxButtons.OK, MessageBoxIcon.Error);
        return 1;
      }
    }
  }
}
