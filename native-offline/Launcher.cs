using System.Diagnostics;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text.Json;
using System.Windows.Forms;

namespace Shaiya.Offline;
internal record Slot(string Id, string Name, string Faction, string Created) {
 public override string ToString()=> $"{Name}  ·  {(Faction=="light"?"Luz":"Furia")}";
}
internal static class Program {
 [STAThread] static void Main() { ApplicationConfiguration.Initialize(); Application.Run(new Launcher()); }
}
internal sealed class Launcher:Form {
 const string ClientHash="509c4a8fbe4d5292961fdfb6d1045795a7bb5970fcf2560fd1070aee18273c2d";
 readonly string home=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"Dreynox","ShaiyaOffline");
 readonly TextBox client=new(){Dock=DockStyle.Fill,ReadOnly=true};
 readonly TextBox name=new(){PlaceholderText="Nombre de la partida",Dock=DockStyle.Fill,MaxLength=60};
 readonly ComboBox faction=new(){Dock=DockStyle.Fill,DropDownStyle=ComboBoxStyle.DropDownList};
 readonly ListBox slots=new(){Dock=DockStyle.Fill,IntegralHeight=false};
 readonly TextBox log=new(){Dock=DockStyle.Fill,Multiline=true,ReadOnly=true,ScrollBars=ScrollBars.Vertical};
 readonly Button start=new(){Text="Iniciar partida",AutoSize=true};
 readonly Button stop=new(){Text="Cerrar sesión",AutoSize=true,Enabled=false};
 readonly List<Process> services=new();
 readonly HttpClient http=new(){Timeout=TimeSpan.FromSeconds(2)};
 readonly SemaphoreSlim cleanupGate=new(1,1);
 FileStream? slotLock;Process? game;bool busy;bool allowClose;
 string token="",password="",logFile="";
 public Launcher(){
  Text="Shaiya Offline · Cliente original ps0032";Size=new(1040,740);MinimumSize=new(820,620);StartPosition=FormStartPosition.CenterScreen;
  Font=new("Segoe UI",10);BackColor=Color.FromArgb(20,25,34);ForeColor=Color.Gainsboro;
  var grid=new TableLayoutPanel{Dock=DockStyle.Fill,Padding=new(20),ColumnCount=2,RowCount=7};
  grid.ColumnStyles.Add(new(SizeType.Percent,65));grid.ColumnStyles.Add(new(SizeType.Percent,35));
  grid.RowStyles.Add(new(SizeType.Absolute,52));grid.RowStyles.Add(new(SizeType.Absolute,46));grid.RowStyles.Add(new(SizeType.Absolute,56));grid.RowStyles.Add(new(SizeType.Absolute,48));grid.RowStyles.Add(new(SizeType.Percent,45));grid.RowStyles.Add(new(SizeType.Absolute,46));grid.RowStyles.Add(new(SizeType.Percent,55));
  var title=new Label{Text="PARTIDAS LOCALES  /  PS0032",Font=new("Segoe UI",17,FontStyle.Bold),Dock=DockStyle.Fill};grid.Controls.Add(title,0,0);grid.SetColumnSpan(title,2);
  grid.Controls.Add(client,0,1);var browse=Button("Carpeta del cliente…",ChooseClient);grid.Controls.Add(browse,1,1);
  var info=new Label{Dock=DockStyle.Fill,Text="Selecciona la instalación completa que contiene game.exe + data.sah/data.saf.\nNo reemplaza el EXE original. Solo comunica con servicios en 127.0.0.1.",AutoEllipsis=true};grid.Controls.Add(info,0,2);grid.SetColumnSpan(info,2);
  grid.Controls.Add(name,0,3);faction.Items.AddRange(new object[]{"Luz","Furia"});faction.SelectedIndex=0;grid.Controls.Add(faction,1,3);
  grid.Controls.Add(slots,0,4);grid.SetColumnSpan(slots,2);
  var actions=new FlowLayoutPanel{Dock=DockStyle.Fill,WrapContents=false};actions.Controls.Add(Button("Crear partida",CreateSlot));actions.Controls.Add(start);actions.Controls.Add(stop);actions.Controls.Add(Button("Enviar a papelera",Trash));actions.Controls.Add(Button("Abrir registros",OpenLogs));grid.Controls.Add(actions,0,5);grid.SetColumnSpan(actions,2);
  grid.Controls.Add(log,0,6);grid.SetColumnSpan(log,2);Controls.Add(grid);
  start.Click+=async(_,_)=>await Start();stop.Click+=async(_,_)=>await Stop();
  FormClosing+=async(_,e)=>{if(allowClose)return;if(busy||game!=null||services.Count>0){e.Cancel=true;if(!busy&&await Stop()){allowClose=true;Close();}}};
  Directory.CreateDirectory(Path.Combine(home,"partidas"));Directory.CreateDirectory(Path.Combine(home,"papelera"));Directory.CreateDirectory(Path.Combine(home,"registros"));
  try{var c=Path.Combine(home,"cliente.txt");if(File.Exists(c))client.Text=File.ReadAllText(c);}catch(Exception e){Append(e.Message);}
  RefreshSlots();Append("Este lanzador inicia tu cliente original con servicios locales. Las partidas Flutter usan otro almacén y no son intercambiables. Las reglas y definiciones del backend son las de la referencia publicada, no todos los datos personalizados de tu servidor.");
 }
 static Button Button(string text,EventHandler click){var b=new Button{Text=text,AutoSize=true,Padding=new(5)};b.Click+=click;return b;}
 void Append(string text){
  if(IsDisposed)return;if(InvokeRequired){try{BeginInvoke(new Action(()=>Append(text)));}catch(InvalidOperationException){}return;}
  if(token.Length>0)text=text.Replace(token,"<sesión>");if(password.Length>0)text=text.Replace(password,"<clave-local>");
  var line=DateTime.Now.ToString("HH:mm:ss")+"  "+text+Environment.NewLine;
  log.AppendText(line);if(log.TextLength>100000)log.Text=log.Text[^60000..];
  if(logFile.Length>0)try{File.AppendAllText(logFile,line);}catch(IOException){}
 }
 void Error(Exception e){Append(e.Message);MessageBox.Show(this,e.Message,"No se ha iniciado o guardado la operación",MessageBoxButtons.OK,MessageBoxIcon.Warning);}
 void ChooseClient(object? s,EventArgs e){if(busy||game!=null)return;using var d=new FolderBrowserDialog{Description="Instalación completa del cliente ps0032"};if(d.ShowDialog(this)==DialogResult.OK){client.Text=d.SelectedPath;File.WriteAllText(Path.Combine(home,"cliente.txt"),client.Text);}}
 string SlotPath(Slot s){if(!Guid.TryParseExact(s.Id,"N",out _))throw new InvalidDataException("ID de partida inválido.");var p=Path.Combine(home,"partidas",s.Id);if(new DirectoryInfo(p).LinkTarget!=null)throw new IOException("No se admiten enlaces en partidas.");return p;}
 void RefreshSlots(){
  slots.Items.Clear();foreach(var folder in Directory.EnumerateDirectories(Path.Combine(home,"partidas"))){try{if(new DirectoryInfo(folder).LinkTarget!=null)continue;var s=JsonSerializer.Deserialize<Slot>(File.ReadAllText(Path.Combine(folder,"partida.json")));if(s!=null&&Path.GetFileName(folder)==s.Id&&s.Faction is "light" or "fury")slots.Items.Add(s);}catch(Exception e){Append("Partida no leída, conservada intacta: "+e.Message);}}
  if(slots.Items.Count>0)slots.SelectedIndex=0;
 }
 void CreateSlot(object? sender,EventArgs e){try{if(busy||game!=null)return;var n=name.Text.Trim();if(n.Length<1||n.Any(char.IsControl))throw new ArgumentException("Escribe un nombre de 1 a 60 caracteres.");var slot=new Slot(Guid.NewGuid().ToString("N"),n,faction.SelectedIndex==0?"light":"fury",DateTimeOffset.UtcNow.ToString("O"));var path=SlotPath(slot);Directory.CreateDirectory(path);File.WriteAllText(Path.Combine(path,"partida.json"),JsonSerializer.Serialize(slot,new JsonSerializerOptions{WriteIndented=true}));RefreshSlots();for(int i=0;i<slots.Items.Count;i++)if(((Slot)slots.Items[i]).Id==slot.Id)slots.SelectedIndex=i;}catch(Exception x){Error(x);}}
 void Trash(object? sender,EventArgs e){try{if(busy||game!=null||services.Count>0)return;if(slots.SelectedItem is not Slot s)return;if(MessageBox.Show(this,"¿Mover esta partida a la papelera? No se borrarán sus archivos.","Partida",MessageBoxButtons.YesNo)!=DialogResult.Yes)return;Directory.Move(SlotPath(s),Path.Combine(home,"papelera",s.Id+"-"+DateTime.UtcNow.Ticks));RefreshSlots();}catch(Exception x){Error(x);}}
 void OpenLogs(object? sender,EventArgs e){Process.Start(new ProcessStartInfo("explorer.exe",Path.Combine(home,"registros")){UseShellExecute=true});}
 static bool Linked(string p)=>new FileInfo(p).LinkTarget!=null;
 async Task Start(){
  if(busy||game!=null||services.Count>0)return;busy=true;start.Enabled=false;
  try{
   if(slots.SelectedItem is not Slot s)throw new ArgumentException("Crea o elige una partida.");
   var dir=Path.GetFullPath(client.Text);var exe=Path.Combine(dir,"game.exe");
   if(!File.Exists(exe)||Linked(exe))throw new IOException("Falta un game.exe regular en la carpeta elegida.");
   await using(var f=File.OpenRead(exe)){if(Convert.ToHexString(await SHA256.HashDataAsync(f)).ToLowerInvariant()!=ClientHash)throw new InvalidDataException("Este ejecutable no coincide con el perfil ps0032 verificado. No se parcheará ni ejecutará automáticamente.");}
   foreach(var f in new[]{"data.sah","data.saf"})if(!File.Exists(Path.Combine(dir,f)))throw new IOException("Falta "+f+". Este cliente nativo todavía utiliza el par SAH/SAF; la carga de carpeta DATA está en el cliente Flutter.");
   foreach(var port in new[]{5000,5001,30800,30810}){var probe=new TcpListener(IPAddress.Loopback,port);try{probe.Start();}catch(SocketException){throw new IOException("El puerto "+port+" está ocupado. No se detendrá ningún proceso ajeno.");}finally{probe.Stop();}}
   var path=SlotPath(s);var lockPath=Path.Combine(path,"launcher.lock");if(File.Exists(lockPath)&&Linked(lockPath))throw new IOException("Enlace de bloqueo no permitido.");slotLock=new FileStream(lockPath,FileMode.OpenOrCreate,FileAccess.ReadWrite,FileShare.None);
   token=Convert.ToHexString(RandomNumberGenerator.GetBytes(24));password=Convert.ToHexString(RandomNumberGenerator.GetBytes(16));
   logFile=Path.Combine(home,"registros","sesion-"+DateTime.UtcNow.ToString("yyyyMMdd-HHmmss")+"-"+s.Id+".log");Append("Iniciando "+s+". Las bases SQLite permanecen en esta partida.");
   foreach(var item in new[]{("login",5000),("world",5001)}){
    var runtime=Path.Combine(AppContext.BaseDirectory,"runtime",item.Item1);var binary=Path.Combine(runtime,"Imgeneus."+(item.Item1=="login"?"Login":"World")+".exe");
    if(!File.Exists(binary))throw new IOException("Falta el servicio "+binary+". Extrae el paquete completo.");
    var info=new ProcessStartInfo(binary){WorkingDirectory=runtime,UseShellExecute=false,CreateNoWindow=true,RedirectStandardOutput=true,RedirectStandardError=true};
    info.Environment["SHAIYA_OFFLINE_SLOT"]=path;info.Environment["SHAIYA_OFFLINE_FACTION"]=s.Faction;info.Environment["SHAIYA_OFFLINE_PASSWORD"]=password;info.Environment["SHAIYA_OFFLINE_TOKEN"]=token;info.Environment["ASPNETCORE_ENVIRONMENT"]="Production";info.Environment["DOTNET_ENVIRONMENT"]="Production";
    var p=Process.Start(info)??throw new IOException("No se pudo iniciar el servicio.");services.Add(p);p.OutputDataReceived+=(_,x)=>{if(x.Data!=null)Append(x.Data);};p.ErrorDataReceived+=(_,x)=>{if(x.Data!=null)Append(x.Data);};p.BeginOutputReadLine();p.BeginErrorReadLine();
    var deadline=DateTime.UtcNow.AddSeconds(100);bool ready=false;
    while(DateTime.UtcNow<deadline&&!p.HasExited){try{using var req=new HttpRequestMessage(HttpMethod.Get,"http://127.0.0.1:"+item.Item2+"/offline/status");req.Headers.Authorization=new AuthenticationHeaderValue("Bearer",token);using var response=await http.SendAsync(req);if(response.IsSuccessStatusCode){using var json=JsonDocument.Parse(await response.Content.ReadAsStringAsync());ready=json.RootElement.GetProperty("ready").GetBoolean();if(ready)break;}}catch(Exception x)when(x is HttpRequestException or TaskCanceledException or JsonException){}await Task.Delay(500);}
    if(!ready)throw new IOException(item.Item1+" no quedó listo. Consulta el registro de esta sesión.");
   }
   var launch=new ProcessStartInfo(exe){WorkingDirectory=dir,UseShellExecute=false};launch.ArgumentList.Add("start");launch.ArgumentList.Add("127.0.0.1");launch.ArgumentList.Add("localplayer:"+password);
   game=Process.Start(launch)??throw new IOException("No se pudo abrir el cliente.");stop.Enabled=true;Append("Cliente iniciado. Cierra desde el juego para permitir su guardado normal. No publiques claves, partidas ni archivos DATA en GitHub.");
   _=ObserveGame(game);
  }catch(Exception x){Error(x);await Cleanup();}finally{busy=false;start.Enabled=game==null;}
 }
 async Task ObserveGame(Process process){await process.WaitForExitAsync();if(game!=process)return;Append("El cliente terminó. Esperando el guardado del servicio local…");await Task.Delay(2500);await Cleanup();}
 async Task<bool> Stop(){
  if(busy)return false;busy=true;stop.Enabled=false;
  try{if(game!=null&&!game.HasExited){game.CloseMainWindow();var finished=await Task.WhenAny(game.WaitForExitAsync(),Task.Delay(15000));if(game!=null&&!game.HasExited){Append("El juego sigue abierto. Sal desde su menú para guardar; no se forzará el cierre.");return false;}}await Task.Delay(2000);await Cleanup();return true;}
  finally{busy=false;stop.Enabled=game!=null;start.Enabled=game==null;}
 }
 async Task Cleanup(){
  await cleanupGate.WaitAsync();
  try{
  foreach(var p in services.AsEnumerable().Reverse()){try{if(!p.HasExited){p.Kill(entireProcessTree:true);await p.WaitForExitAsync();}p.Dispose();}catch(InvalidOperationException){}catch(System.ComponentModel.Win32Exception x){Append(x.Message);}}
  services.Clear();game?.Dispose();game=null;slotLock?.Dispose();slotLock=null;stop.Enabled=false;start.Enabled=true;token="";password="";
  }finally{cleanupGate.Release();}
 }
}
