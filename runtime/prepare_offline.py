#!/usr/bin/env python3
"""Prepare the pinned GPL Imgeneus reference for isolated offline validation.
This source adaptation is not a claim that the native game has been tested.
No original game data, executables, passwords or user databases are uploaded.
"""
from pathlib import Path
import hashlib, json, re, sys
import xml.etree.ElementTree as ET
ROOT = Path(sys.argv[1]).resolve()
VERSION = '10.0.12'
CHANGES = []
def read(name):
    return (ROOT/name).read_text(encoding='utf-8-sig')
def write(name, text):
    p = ROOT/name
    before = hashlib.sha256(p.read_bytes()).hexdigest() if p.exists() else None
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text, encoding='utf-8')
    CHANGES.append({'path':name,'before':before,'after':hashlib.sha256(p.read_bytes()).hexdigest()})
def replace(name, old, new):
    s=read(name)
    if s.count(old)!=1: raise RuntimeError('Contract changed: '+name+' '+old[:45])
    write(name,s.replace(old,new))
if not (ROOT/'Imgeneus.sln').is_file(): raise SystemExit('Pinned Imgeneus checkout required.')
for p in sorted(ROOT.rglob('*.csproj')):
    if 'tests' in p.relative_to(ROOT).as_posix().lower(): continue
    tree=ET.fromstring(p.read_text(encoding='utf-8-sig'))
    for group in tree.findall('PropertyGroup'):
        for key in ['TargetFramework','TargetFrameworks']:
            n=group.find(key)
            if n is not None and n.text and ('net6.0' in n.text or 'net5.0' in n.text): n.tag='TargetFramework'; n.text='net10.0'
    for group in tree.findall('ItemGroup'):
        for ref in list(group.findall('PackageReference')):
            name=ref.get('Include','')
            if name in {'Pomelo.EntityFrameworkCore.MySql','Microsoft.EntityFrameworkCore.SqlServer','Microsoft.VisualStudio.Web.CodeGeneration.Design','Microsoft.AspNetCore'} or name=='Microsoft.EntityFrameworkCore.Tools': group.remove(ref); continue
            if name.startswith(('Microsoft.EntityFrameworkCore','Microsoft.AspNetCore.Identity','Microsoft.AspNetCore.Components','Microsoft.AspNetCore.SignalR.Client','Microsoft.Extensions.','System.Text.Encodings.Web')): ref.set('Version',VERSION)
    group=ET.SubElement(tree,'PropertyGroup')
    ET.SubElement(group,'DefineConstants').text='$(DefineConstants);SHAIYA_US;DREYNOX_OFFLINE'
    ET.SubElement(group,'RestorePackagesWithLockFile').text='true'
    if p.name in {'Imgeneus.Database.csproj','Imgeneus.Authentication.csproj'}:
        group=ET.SubElement(tree,'ItemGroup')
        ET.SubElement(group,'PackageReference',Include='Microsoft.EntityFrameworkCore.Sqlite',Version=VERSION)
        ET.SubElement(group,'Compile',Remove='Migrations/**/*.cs')
        ET.SubElement(group,'Compile',Remove='**/DatabaseFactory.cs')
    if p.name=='Imgeneus.Core.csproj':
        group=ET.SubElement(tree,'ItemGroup'); ET.SubElement(group,'FrameworkReference',Include='Microsoft.AspNetCore.App')
    if p.name=='Imgeneus.Authentication.csproj':
        group=ET.SubElement(tree,'ItemGroup'); ET.SubElement(group,'ProjectReference',Include='../../../src/Imgeneus.Core/Imgeneus.Core.csproj')
    ET.indent(tree,space='  ')
    write(p.relative_to(ROOT).as_posix(),ET.tostring(tree,encoding='unicode'))
write('src/Imgeneus.Core/Offline/OfflinePaths.cs', '''using System;
using System.IO;
namespace Imgeneus.Core.Offline {
 public static class OfflinePaths {
  public static string Root { get {
   var value=Environment.GetEnvironmentVariable("SHAIYA_OFFLINE_SLOT");
   if(String.IsNullOrWhiteSpace(value)||!Path.IsPathFullyQualified(value)||!Directory.Exists(value))throw new InvalidOperationException("Existing private offline slot required.");
   var info=new DirectoryInfo(value); if(info.LinkTarget!=null)throw new InvalidOperationException("Slot links refused."); return info.FullName;
  }}
  public static string Database(string name){
   if(name!="world"&&name!="users")throw new ArgumentException("Unknown database");
   var path=Path.Combine(Root,name+".sqlite");
   if(File.Exists(path)&&new FileInfo(path).LinkTarget!=null)throw new InvalidOperationException("Database links refused."); return path;
  }
  public static string RequireSecret(string name){
   var s=Environment.GetEnvironmentVariable(name);
   if(String.IsNullOrEmpty(s)||s.Length<16||s.Length>128||s.Contains('\\r')||s.Contains('\\n'))throw new InvalidOperationException("Missing per-session secret: "+name); return s;
  }
 }
}
''')
for path,name in [('src/Imgeneus.Database/ConfigureDatabase.cs','world'),('submodules/Imgeneus.Authentication/Imegeneus.Authentication/Connection/ConfigureDatabase.cs','users')]:
    s=read(path); start=s.index('            optionsBuilder.UseMySql('); end=s.index('            return optionsBuilder;',start)
    s=s[:start]+f'''            var connection=new Microsoft.Data.Sqlite.SqliteConnectionStringBuilder {{
                DataSource=Imgeneus.Core.Offline.OfflinePaths.Database("{name}"),
                Mode=Microsoft.Data.Sqlite.SqliteOpenMode.ReadWriteCreate,
                Cache=Microsoft.Data.Sqlite.SqliteCacheMode.Private,ForeignKeys=true,DefaultTimeout=15,
            }};
            optionsBuilder.UseSqlite(connection.ToString());
'''+s[end:]
    write(path,s)
for path in ['src/Imgeneus.Database/Context/DatabaseContext.cs','submodules/Imgeneus.Authentication/Imegeneus.Authentication/Context/UsersContext.cs']:
    s=read(path).replace('                var tableName = entityType.GetTableName();','                foreach(var property in entityType.GetProperties()) property.SetColumnType(null);\n                var tableName = entityType.GetTableName();')
    s=s.replace('this.Database.Migrate()','this.Database.EnsureCreated()').replace('Database.Migrate();','Database.EnsureCreated();')
    write(path,s)
replace('src/Imgeneus.GameDefinitions/GameDefinitionsPreloder.cs','_logger.LogError($"Error during preloading game definitions: {ex.Message}");','_logger.LogError($"Error during preloading game definitions: {ex.Message}");\n                throw;')
path='src/Imgeneus.Game/Player/Config/CharacterConfiguration.cs'
s=read(path); s=re.sub(r'\[JsonProperty\("HP"\)\](\s+public\s+\w+\s+SP)',r'[JsonProperty("SP")]\1',s); write(path,s)
replace('src/Imgeneus.World/WorldServerStartup.cs','                logsManager.Connect(logsConnectionString);','                throw new InvalidOperationException("External storage disabled in offline mode.");')
for project,port in [('Imgeneus.Login',5000),('Imgeneus.World',5001)]:
    replace(f'src/{project}/Program.cs','                    webBuilder.UseStartup<',f'                    webBuilder.UseUrls("http://127.0.0.1:{port}").UseStartup<')
    cfg=json.loads(read(f'src/{project}/appsettings.json')); cfg['AllowedHosts']='127.0.0.1;localhost'; cfg['TcpServer']['Host']='127.0.0.1'; cfg['TcpServer']['Backlog']=8
    cfg['Logging']['LogLevel']['Default']='Information'; cfg.pop('Database',None); cfg.pop('UsersDatabase',None)
    if 'WorldServer' in cfg: cfg['WorldServer'].update(Host='127.0.0.1',Name='Partida local',MaximumNumberOfConnections=1,WelcomeMessage='Laboratorio local',LogsStorageConnectionString='')
    write(f'src/{project}/appsettings.json',json.dumps(cfg,indent=2,ensure_ascii=False)); write(f'src/{project}/appsettings.Development.json','{}\n')
gate=r'''            var offlineToken=Imgeneus.Core.Offline.OfflinePaths.RequireSecret("SHAIYA_OFFLINE_TOKEN");
            app.Use(async (ctx,next) => {
                if (ctx.Connection.RemoteIpAddress == null || !System.Net.IPAddress.IsLoopback(ctx.Connection.RemoteIpAddress) || ctx.Request.Headers.ContainsKey("Origin")) {ctx.Response.StatusCode=403;return;}
                if (ctx.Request.Path.StartsWithSegments("/offline/status")) {
                    if (!System.Security.Cryptography.CryptographicOperations.FixedTimeEquals(System.Text.Encoding.UTF8.GetBytes(ctx.Request.Headers["Authorization"].ToString()),System.Text.Encoding.UTF8.GetBytes("Bearer "+offlineToken))) {ctx.Response.StatusCode=401;return;}
                    ctx.Response.ContentType="application/json";
                    await ctx.Response.WriteAsync("{\"runtime\":\"imgeneus-offline\",\"protocol\":\"ps0032\",\"ready\":true}");return;
                }
                if (!ctx.Request.Path.StartsWithSegments("/inter_server") || ctx.Request.Headers["X-Offline-Token"] != offlineToken) {ctx.Response.StatusCode=403;return;}
                await next();
            });
'''
for path in ['src/Imgeneus.Login/LoginServerStartup.cs','src/Imgeneus.World/WorldServerStartup.cs']:
    s='using Microsoft.AspNetCore.Http;\n'+read(path); s=s.replace('            app.UseStaticFiles();',gate)
    s=s.replace('builder.AllowAnyOrigin().AllowAnyMethod().AllowAnyHeader();','builder.WithOrigins("http://127.0.0.1").AllowAnyMethod().AllowAnyHeader();'); write(path,s)
replace('src/Imgeneus.InterServer/Client/ISClient.cs','.WithUrl(_config.Endpoint)','.WithUrl(_config.Endpoint, options => {\n                        if (!new Uri(_config.Endpoint).IsLoopback) throw new InvalidOperationException("Interserver must be loopback.");\n                        options.Headers.Add("X-Offline-Token", Imgeneus.Core.Offline.OfflinePaths.RequireSecret("SHAIYA_OFFLINE_TOKEN"));\n                    })')
write('OFFLINE_PORT_MANIFEST.json',json.dumps({'schema':1,'upstream':'0ce355594d521c3a06a08f24d0a9b60ebc8a459f','authenticationReference':'77b3a65e9a0ba60f83e1aa452e9f0b997ea27a70','target':'net10.0','protocol':'SHAIYA_US/ps0032','warning':'No native client compatibility or complete gameplay claim. SQLite saves require explicit bootstrap and schema validation.','changes':CHANGES},indent=2))
print(f'Prepared {len(CHANGES)} source changes. Native compatibility is not asserted.')
