#!/usr/bin/env python3
"""Second pass for the pinned offline reference. No user data are bundled."""
from pathlib import Path
import hashlib, json, re, sys
import xml.etree.ElementTree as ET
root=Path(sys.argv[1]).resolve()
def read(p): return (root/p).read_text(encoding='utf-8-sig')
def put(p,s):
 p=root/p;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(s,encoding='utf-8')
def replace(p,a,b):
 s=read(p)
 if s.count(a)!=1: raise RuntimeError('Contract changed: '+p+' '+a[:60])
 put(p,s.replace(a,b))
legacy={'Microsoft.AspNet.SignalR.Client','Microsoft.AspNet.SignalR.SelfHost','Microsoft.AspNetCore.SignalR.Core','Microsoft.AspNetCore.Hosting.Abstractions','Microsoft.AspNetCore.Http.Connections','System.Collections','System.Collections.Concurrent','System.ObjectModel'}
for p in root.rglob('*.csproj'):
 if 'tests' in p.relative_to(root).as_posix().lower():continue
 tree=ET.fromstring(p.read_text(encoding='utf-8-sig'))
 removed=False
 for group in tree.findall('ItemGroup'):
  for item in list(group.findall('PackageReference')):
   name=item.get('Include','')
   if name in legacy:group.remove(item);removed=True
   elif name=='Newtonsoft.Json':item.set('Version','13.0.4')
 if removed:
  group=ET.SubElement(tree,'ItemGroup');ET.SubElement(group,'FrameworkReference',Include='Microsoft.AspNetCore.App')
 ET.indent(tree,space='  ');put(p.relative_to(root).as_posix(),ET.tostring(tree,encoding='unicode'))
# The seed uses SQL mode values 1..4; the actual C# enum is 0..3. Remapping is
# explicit and kept in the manifest, not a silent alteration of the source.
seed=read('src/Imgeneus.Database/Migrations/sql/InitLevels.sql')
rows=[]
for a,b,c,d in re.findall(r'\((\d+),\s*(\d+),\s*(\d+),\s*(\d+)\)',seed):
 i,level,mode,exp=map(int,(a,b,c,d));assert 1<=mode<=4 and 1<=level<=80 and 0<=exp<=0xffffffff
 rows.append({'id':i,'level':level,'mode':mode-1,'exp':exp})
assert len(rows)==320 and len({(r['mode'],r['level']) for r in rows})==320
put('src/Offline.Storage/levels.json',json.dumps(rows,separators=(',',':')))
put('src/Offline.Storage/Offline.Storage.csproj','''<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><TargetFramework>net10.0</TargetFramework><ImplicitUsings>enable</ImplicitUsings><Nullable>enable</Nullable></PropertyGroup><ItemGroup>
<ProjectReference Include="../Imgeneus.Core/Imgeneus.Core.csproj"/><ProjectReference Include="../Imgeneus.Database/Imgeneus.Database.csproj"/><ProjectReference Include="../../submodules/Imgeneus.Authentication/Imegeneus.Authentication/Imgeneus.Authentication.csproj"/>
<EmbeddedResource Include="levels.json"/>
</ItemGroup></Project>''')
put('src/Offline.Storage/SlotBootstrap.cs',r'''using System.Data.Common;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Imgeneus.Core.Offline;
using Imgeneus.Database.Context;
using Imgeneus.Database.Entities;
using Imgeneus.Authentication.Context;
using Imgeneus.Authentication.Entities;
using Microsoft.AspNetCore.Identity;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
namespace Offline.Storage;
public static class SlotBootstrap {
 public const string Username="localplayer";
 public static string Connection(string name) => new SqliteConnectionStringBuilder { DataSource=OfflinePaths.Database(name),Mode=SqliteOpenMode.ReadWriteCreate,ForeignKeys=true,DefaultTimeout=15 }.ToString();
 public static DatabaseContext World()=>new(new DbContextOptionsBuilder<DatabaseContext>().UseSqlite(Connection("world")).Options);
 public static UsersContext Users()=>new(new DbContextOptionsBuilder<UsersContext>().UseSqlite(Connection("users")).Options);
 static string Schema(DbContext db)=>Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(db.Database.GenerateCreateScript())));
 static object? Scalar(DbConnection db,string sql){using var cmd=db.CreateCommand();cmd.CommandText=sql;return cmd.ExecuteScalar();}
 static void Exec(DbConnection db,string sql){using var cmd=db.CreateCommand();cmd.CommandText=sql;cmd.ExecuteNonQuery();}
 public static void ValidateSchema(DbContext db,string name) {
  var file=OfflinePaths.Database(name);var existing=File.Exists(file)&&new FileInfo(file).Length>0;
  if(existing){db.Database.OpenConnection();var cn=db.Database.GetDbConnection();
   if(!String.Equals(Scalar(cn,"PRAGMA quick_check")?.ToString(),"ok",StringComparison.OrdinalIgnoreCase))throw new InvalidDataException("SQLite integrity failed: "+name);
   var has=Convert.ToInt32(Scalar(cn,"SELECT count(*) FROM sqlite_master WHERE type='table' AND name='offline_schema'"));
   if(has!=1)throw new InvalidDataException("Unknown save schema; automatic conversion refused: "+name);
   if(Scalar(cn,"SELECT hash FROM offline_schema WHERE id=1")?.ToString()!=Schema(db))throw new InvalidDataException("Save schema differs from this runtime: "+name);
  } else {
   db.Database.EnsureCreated();db.Database.OpenConnection();var cn=db.Database.GetDbConnection();
   Exec(cn,"CREATE TABLE offline_schema(id INTEGER PRIMARY KEY CHECK(id=1), hash TEXT NOT NULL)");
   using var cmd=cn.CreateCommand();cmd.CommandText="INSERT INTO offline_schema(id,hash) VALUES(1,$hash)";
   var p=cmd.CreateParameter();p.ParameterName="$hash";p.Value=Schema(db);cmd.Parameters.Add(p);cmd.ExecuteNonQuery();
  }
  Exec(db.Database.GetDbConnection(),"PRAGMA journal_mode=WAL");
  Exec(db.Database.GetDbConnection(),"PRAGMA synchronous=FULL");
 }
 record LevelRow(uint id,ushort level,byte mode,uint exp);
 public static void Initialize(bool createIdentity) {
  var faction=Environment.GetEnvironmentVariable("SHAIYA_OFFLINE_FACTION");
  if(faction!="light"&&faction!="fury")throw new InvalidOperationException("Choose light or fury for the slot.");
  var lockPath=Path.Combine(OfflinePaths.Root,"bootstrap.lock");
  if(File.Exists(lockPath)&&new FileInfo(lockPath).LinkTarget!=null)throw new InvalidOperationException("Save lock links refused.");
  using var guard=new FileStream(lockPath,FileMode.OpenOrCreate,FileAccess.ReadWrite,FileShare.None);
  using var world=World();ValidateSchema(world,"world");
  using var seed=typeof(SlotBootstrap).Assembly.GetManifestResourceStream("Offline.Storage.levels.json")??throw new InvalidDataException("Level seed absent.");
  var levels=JsonSerializer.Deserialize<List<LevelRow>>(seed)??throw new InvalidDataException("Level seed invalid.");
  if(!world.Levels.Any()) {using var tx=world.Database.BeginTransaction();world.Levels.AddRange(levels.Select(l=>new DbLevel {Id=l.id,Level=l.level,Mode=(Mode)l.mode,Exp=l.exp}));world.SaveChanges();tx.Commit();}
  if(world.Levels.Count()!=320)throw new InvalidDataException("Levels are incomplete; explicit migration required.");
  var expected=faction=="light"?Fraction.Light:Fraction.Dark;
  var country=world.UsersModeAndCountry.SingleOrDefault(c=>c.UserId==1);
  if(country==null){world.UsersModeAndCountry.Add(new DbUserModeAndCountry {UserId=1,Country=expected,MaxMode=Mode.Ultimate});world.SaveChanges();}
  else if(country.Country!=expected)throw new InvalidOperationException("Slot faction cannot be silently changed.");
  if(createIdentity){using var users=Users();ValidateSchema(users,"users");
   if(users.Users.Any(u=>u.Id!=1))throw new InvalidDataException("Only the isolated local account is permitted.");
   var user=users.Users.SingleOrDefault(u=>u.Id==1);
   if(user==null){user=new DbUser {Id=1,UserName=Username,NormalizedUserName=Username.ToUpperInvariant(),Email="local@localhost",NormalizedEmail="LOCAL@LOCALHOST",EmailConfirmed=true};users.Users.Add(user);}
   if(user.UserName!=Username||user.IsDeleted)throw new InvalidDataException("Local account mismatch.");
   user.PasswordHash=new PasswordHasher<DbUser>().HashPassword(user,OfflinePaths.RequireSecret("SHAIYA_OFFLINE_PASSWORD"));
   user.SecurityStamp=Guid.NewGuid().ToString();user.ConcurrencyStamp=Guid.NewGuid().ToString();users.SaveChanges();
  } else {using var users=Users();ValidateSchema(users,"users");if(!users.Users.Any(u=>u.Id==1))throw new InvalidOperationException("Login service must initialize the slot first.");}
 }
}
''')
for project in ['Imgeneus.Login','Imgeneus.World']:
 p=f'src/{project}/{project}.csproj';tree=ET.fromstring(read(p));g=ET.SubElement(tree,'ItemGroup');ET.SubElement(g,'ProjectReference',Include='../Offline.Storage/Offline.Storage.csproj');ET.indent(tree,space='  ');put(p,ET.tostring(tree,encoding='unicode'))
 replace(f'src/{project}/Program.cs','                CreateHostBuilder(args)',f'                Offline.Storage.SlotBootstrap.Initialize({str(project=="Imgeneus.Login").lower()});\n                CreateHostBuilder(args)')
replace('src/Imgeneus.Database/Preload/DatabasePreloader.cs','_logger.LogError($"Error during preloading database: {ex.Message}");','_logger.LogError($"Error during preloading database: {ex.Message}");\n                throw;')
# Body data should not leak into diagnostic logs. No credential text is logged.
put('src/Offline.Verify/Offline.Verify.csproj','''<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><OutputType>Exe</OutputType><TargetFramework>net10.0</TargetFramework><ImplicitUsings>enable</ImplicitUsings><Nullable>enable</Nullable></PropertyGroup><ItemGroup><ProjectReference Include="../Offline.Storage/Offline.Storage.csproj"/></ItemGroup></Project>''')
put('src/Offline.Verify/Program.cs',r'''using Offline.Storage;
using Imgeneus.Database.Entities;
using Microsoft.EntityFrameworkCore;
using System.Security.Cryptography;
using System.Text.Json;
var root=Path.Combine(Path.GetTempPath(),"shaiya-offline-test-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(root);
var checks=new List<string>();
void Check(bool condition,string label){if(!condition)throw new Exception(label);checks.Add(label);}
Environment.SetEnvironmentVariable("SHAIYA_OFFLINE_SLOT",root);Environment.SetEnvironmentVariable("SHAIYA_OFFLINE_FACTION","light");Environment.SetEnvironmentVariable("SHAIYA_OFFLINE_PASSWORD",Convert.ToHexString(RandomNumberGenerator.GetBytes(16)));
try {
 SlotBootstrap.Initialize(true);
 using(var db=SlotBootstrap.World()){
  Check(db.Levels.Count()==320,"320 explicit remapped level records");Check(db.Levels.First(x=>x.Mode==Mode.Beginner&&x.Level==1).Exp==70,"1-based SQL mode remapped to actual 0-based enum");
  Check(db.UsersModeAndCountry.Single().Country==Fraction.Light,"Light slot remains isolated");
  db.Characters.Add(new DbCharacter {Name="Ñandú",UserId=1,Level=1,Slot=0,Race=Race.Human,Class=CharacterProfession.Fighter,Mode=Mode.Normal,Gender=Gender.Man,Map=1,PosX=234.5f,PosY=18.25f,PosZ=611,Gold=765,HealthPoints=100,ManaPoints=80,StaminaPoints=60,CreateTime=DateTime.UtcNow});db.SaveChanges();
 }
 using(var db=SlotBootstrap.World()){var c=db.Characters.Single();Check(c.Name=="Ñandú"&&c.Gold==765&&c.PosX==234.5f,"Unicode character and position survive reopening SQLite");c.PosX+=10;c.Gold+=100;db.SaveChanges();}
 SlotBootstrap.Initialize(true);SlotBootstrap.Initialize(false);
 using(var db=SlotBootstrap.World()){Check(db.Characters.Single().Gold==865,"reinitialization never resets progress");Check(db.Levels.Count()==320,"reinitialization is idempotent");}
 Environment.SetEnvironmentVariable("SHAIYA_OFFLINE_FACTION","fury");bool rejected=false;try{SlotBootstrap.Initialize(true);}catch(InvalidOperationException){rejected=true;}Check(rejected,"faction mutation refused");Environment.SetEnvironmentVariable("SHAIYA_OFFLINE_FACTION","light");
 using(var users=SlotBootstrap.Users()){Check(users.Users.Count()==1,"one private local account, no external registration");Check(!users.Users.Single().PasswordHash!.Contains(Environment.GetEnvironmentVariable("SHAIYA_OFFLINE_PASSWORD")!),"local password is hashed");}
 using(var db=SlotBootstrap.World()){db.Database.ExecuteSqlRaw("UPDATE offline_schema SET hash='incompatible'");}
 rejected=false;try{SlotBootstrap.Initialize(true);}catch(InvalidDataException){rejected=true;}Check(rejected,"schema changes fail closed instead of rewriting save");
 Console.WriteLine(JsonSerializer.Serialize(new {status="passed",scope="SQLite backend synthetic persistence, not native game",checks}));
} finally {Microsoft.Data.Sqlite.SqliteConnection.ClearAllPools();Directory.Delete(root,true);}
''')
put('OFFLINE_BOOTSTRAP_MANIFEST.json',json.dumps({'schema':1,'levelSeedSourceSha256':hashlib.sha256(seed.encode()).hexdigest(),'levelModeMapping':'SQL 1..4 -> C# Mode 0..3','nativeClientValidated':False,'provider':'SQLite','schemaValidation':'CreateScript SHA-256 stored within each database','localAccount':'private per-slot, no external account'},indent=2))
print('Offline bootstrap and persistence verification generated.')
