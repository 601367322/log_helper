import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:bot_toast/bot_toast.dart';
import 'package:cross_file/cross_file.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:fl_shared_link/fl_shared_link.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_storage/get_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tencent_cos/tencent_cos.dart';
import 'package:path/path.dart' as p;
import 'WindowSizeService.dart';
import 'logutil.dart';
import 'package:file_open_handler/file_open_handler.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    final WindowSizeService windowSizeService = WindowSizeService();
    windowSizeService.initialize();
  }
  //日志
  await LogUtil().initLogger();

  void reportErrorAndLog(FlutterErrorDetails details) {
    final errorMsg = {
      "exception": details.exceptionAsString(),
      "stackTrace": details.stack.toString(),
    };
    logger.e("reportErrorAndLog : $errorMsg");
  }

  FlutterErrorDetails makeDetails(Object error, StackTrace stackTrace) {
    // 构建错误信息
    return FlutterErrorDetails(stack: stackTrace, exception: error);
  }

  FlutterError.onError = (FlutterErrorDetails details) {
    //获取 widget build 过程中出现的异常错误
    reportErrorAndLog(details);
  };

  runZonedGuarded(
    () {
      runApp(const MyApp());
    },
    (error, stackTrace) {
      //没被我们catch的异常
      reportErrorAndLog(makeDetails(error, stackTrace));
    },
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      debugShowCheckedModeBanner: false,
      builder: BotToastInit(),
      navigatorObservers: [BotToastNavigatorObserver()],
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(title: '日志解析工具'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final List<XFile> _list = [];
  late GetStorage box;

  bool _dragging0 = false;
  bool _dragging1 = false;
  bool openAlog = true;
  String pythonPath = "";
  String pythonPathFlag = "pythonPath";
  bool uploading = false;
  String openAlogFlag = "openAlog";
  var clog = "", xlog = "";
  String secretId = "";
  String secretKey = "";
  String bucketName = "";
  String region = "";

  final _inputFocusNode = FocusNode();
  final _fileOpenHandlerPlugin = FileOpenHandler();
  String? openedFile;

  @override
  void initState() {
    super.initState();

    //初始化Cos
    rootBundle.loadString(".cos").then((value) {
      Map<String, dynamic> str = jsonDecode(value);
      secretId = str["secretId"]!;
      secretKey = str["secretKey"]!;
      bucketName = str["bucketName"]!;
      region = str["region"]!;
    });

    //初始化一些默认值
    getApplicationSupportDirectory().then((value) async {
      box = GetStorage("logStorage", value.path, null);
      await GetStorage.init("logStorage");
      setState(() {
        openAlog = box.hasData(openAlogFlag) ? box.read(openAlogFlag) : true;
        pythonPath =
        box.hasData(pythonPathFlag) ? box.read(pythonPathFlag) : "";
      });

      initPlatformState();
    });

    //将脚本从项目copy到磁盘
    copyScriptToDesk("decompress_clog.py").then((value) => clog = value);
    copyScriptToDesk("decode_mars_nocrypt_log_file.py")
        .then((value) => xlog = value);
  }

  Future<void> initPlatformState() async {
    try {
      _fileOpenHandlerPlugin.setOnFileDroppedCallback((String? filepath) {
        if (filepath != null) {
          logger.i("filepath：$filepath");
          onDragDone(
              filepath,
              p.extension(filepath) == ".clog" ||
                  p.extension(filepath) == ".xlog");
        }
      });

      openedFile = await _fileOpenHandlerPlugin.getOpenedFile();
      if (openedFile != null) {
        if (openedFile!.isNotEmpty && openedFile != "no file") {
          logger.i("openedFile：$openedFile");
          onDragDone(
              openedFile!,
              p.extension(openedFile!) == ".clog" ||
                  p.extension(openedFile!) == ".xlog");
        }
      }
    } on PlatformException {
      openedFile = 'Failed to get opened file.';
    }
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          children: [
            if (Platform.isMacOS)
              TextField(
                  controller: TextEditingController.fromValue(
                    TextEditingValue(
                      text: pythonPath,
                      selection: TextSelection.fromPosition(
                        TextPosition(
                            affinity: TextAffinity.downstream,
                            offset: pythonPath.length),
                      ),
                    ),
                  ),
                  focusNode: _inputFocusNode,
                  autofocus: false,
                  onChanged: (value) {
                    setState(() {
                      pythonPath = value;
                    });
                    box.write(pythonPathFlag, value);
                  },
                  decoration: const InputDecoration(
                    isDense: true,
                    prefix: SizedBox(
                      width: 12,
                    ),
                    suffix: SizedBox(
                      width: 12,
                    ),
                    hintText:
                        "请输入python2路径，例如/usr/bin/python2。mac可通过终端'which python2'查找",
                    hintStyle: TextStyle(
                      fontSize: 13,
                    ),
                  )),
            Row(
              children: [
                Row(
                  children: [
                    Checkbox(
                        value: openAlog,
                        onChanged: (value) {
                          setState(() {
                            openAlog = value!;
                          });
                          box.write(openAlogFlag, value);
                        }),
                    const Text("自动打开Alog"),
                  ],
                ),
                const Expanded(child: SizedBox()),
                Text("状态：${uploading ? "正在上传" : "就绪"}"),
                const SizedBox(
                  width: 20,
                ),
              ],
            ),
            Row(
              children: [
                DropTarget(
                  onDragDone: (detail) async {
                    await onDragDone(detail.files[0].path, true);
                  },
                  onDragEntered: (detail) {
                    setState(() {
                      _dragging0 = true;
                    });
                  },
                  onDragExited: (detail) {
                    setState(() {
                      _dragging0 = false;
                    });
                  },
                  child: Container(
                    height: 400,
                    width: 400,
                    color: _dragging0
                        ? Colors.blue.withOpacity(0.4)
                        : Colors.black26,
                    child: _list.isEmpty
                        ? const Center(child: Text("拖入.xlog、.clog日志"))
                        : Text(_list[0].path),
                  ),
                ),
                const SizedBox(
                  width: 1,
                ),
                DropTarget(
                  onDragDone: (detail) async {
                    await onDragDone(detail.files[0].path, false);
                  },
                  onDragEntered: (detail) {
                    setState(() {
                      _dragging1 = true;
                    });
                  },
                  onDragExited: (detail) {
                    setState(() {
                      _dragging1 = false;
                    });
                  },
                  child: Container(
                    height: 400,
                    width: 200,
                    color: _dragging1
                        ? Colors.blue.withOpacity(0.4)
                        : Colors.black26,
                    child: _list.isEmpty
                        ? const Center(child: Text("拖入.log日志"))
                        : Text(_list[0].path),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  //拖动结束
  Future<void> onDragDone(String path, needDecode) async {
    logger.i("onDragDone");
    File finalFile;
    if (needDecode) {
      try {
        if (Platform.isMacOS) {
          if (pythonPath.isEmpty) {
            BotToast.showText(text: "请先输入本机python2路径");
            return;
          }
          var result1 = await runScript("'$pythonPath' '$xlog' '$path'");
          var result2 = await runScript("'$pythonPath' '$clog' '$path'");
        } else {
          await Process.start("python", [xlog, path]);
          await Process.start("python", [clog, path]);
        }
      } catch (e) {
        logger.i(e.toString());
      }
      logger.i(p.extension(path));
      if (p.extension(path) == ".clog") {
        finalFile = File(path.replaceAll(".clog", ".log"));
      } else {
        finalFile = File("$path.log");
      }
    } else {
      finalFile = File(path);
    }
    logger.i("Process Success");
    if (await finalFile.exists()) {
      BotToast.showText(text: "解析成功");
      if (openAlog) {
        BotToast.showText(text: "正在上传");
        String token = "";
        String localPath = finalFile.path;
        String cosPath = "log/${getRandomName()}${p.extension(finalFile.path)}";
        logger.i("正在上传$localPath");
        setState(() {
          uploading = true;
        });
        var url = await COSClient(COSConfig(
          secretId,
          secretKey,
          bucketName,
          region,
        )).putObject(cosPath, localPath, token: token);
        if (url != null) {
          logger.i("上传成功$url");
          Process.run("open", [
            "https://anlog.woa.com?url=https://bingbing-1253488539.cos.ap-nanjing.myqcloud.com/$cosPath"
          ]);
        } else {
          logger.e("上传失败$localPath");
        }
        setState(() {
          uploading = false;
        });
      }
    } else {
      BotToast.showText(text: "日志文件损坏，无法解析");
      return;
    }
  }

  //macos通过原生执行python脚本
  static const channel = MethodChannel('logChannel');

  Future<String> runScript(cmd) async {
    try {
      //原生方法名为callNativeMethond,flutterPara为flutter调用原生方法传入的参数，await等待方法执行
      final result = await channel.invokeMethod('openPython', cmd);
      logger.i(result);
      //如果原生方法执行回调传值给flutter，那下面的代码才会被执行
      return result;
    } on PlatformException catch (e) {
      //抛出异常
      //flutter: PlatformException(001, 进入异常处理, 进入flutter的trycatch方法的catch方法)
      print(e);
    }
    return "";
  }

  //将脚本保存到磁盘
  Future<String> copyScriptToDesk(String path) async {
    final byteData = await rootBundle.load('assets/$path');
    final file = File('${(await getApplicationSupportDirectory()).path}/$path');
    await file.writeAsBytes(byteData.buffer
        .asUint8List(byteData.offsetInBytes, byteData.lengthInBytes));
    return file.path;
  }

  //随机生成6个字符，避免传到云端，日志文件名冲突
  String getRandomName() {
    // 生成一个包含所有英文字母和数字的字符串
    const characters =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

    // 创建一个Random对象
    final random = Random();

    // 生成一个6位的随机字符串
    final codeUnits = List.generate(11, (index) {
      final randomIndex = random.nextInt(characters.length);
      return characters.codeUnitAt(randomIndex);
    });

    final randomString = String.fromCharCodes(codeUnits);
    return randomString;
  }
}
