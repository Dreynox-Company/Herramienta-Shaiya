import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'game/game_client_page.dart';

void main(List<String> args) {
  WidgetsFlutterBinding.ensureInitialized();
  String? dataPath;
  var autoWorld=false;
  for(final arg in args){
    if(arg.startsWith('--data=')) dataPath=arg.substring(7);
    if(arg=='--auto-world') autoWorld=true;
  }
  runApp(ShaiyaGameApp(initialData:dataPath,autoWorld:autoWorld));
}

class ShaiyaGameApp extends StatelessWidget {
  final String? initialData;
  final bool autoWorld;
  const ShaiyaGameApp({super.key,this.initialData,this.autoWorld=false});

  @override
  Widget build(BuildContext context)=>MaterialApp(
    debugShowCheckedModeBanner:false,
    title:'Shaiya',
    locale:const Locale('es'),
    supportedLocales:const [Locale('es')],
    localizationsDelegates:GlobalMaterialLocalizations.delegates,
    theme:ThemeData(
      brightness:Brightness.dark,
      useMaterial3:true,
      scaffoldBackgroundColor:Colors.black,
      colorScheme:const ColorScheme.dark(
        primary:Color(0xffb8524e),
        secondary:Color(0xffd7b06d),
        surface:Color(0xff171716),
      ),
    ),
    home:FlutterGameClientPage(initialData:initialData,autoWorld:autoWorld),
  );
}
