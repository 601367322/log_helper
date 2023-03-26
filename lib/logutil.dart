import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bot_toast/bot_toast.dart';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:synchronized/synchronized.dart' as synchronized;

late Logger logger;

class LogUtil {
  static String? logUserId;
  static String? logUserPhone;

  late PackageInfo packageInfo;
  late String deviceId;
  late Directory tempDir;
  late File logFile;
  late File cursorFile;

  initLogger() async {
    await initLoggerFilePath();

    if (Platform.isMacOS) {}

    logger = Logger(
      level: Level.verbose,
      output: ConsoleOutput(logFile),
      printer: PrettyPrinter(),
      filter: ProductionFilter(),
    );

    clearHistoryLogs();
  }

  void clearHistoryLogs() async {
    try {
      List<FileSystemEntity> list = tempDir.listSync();
      list.forEach((element) {
        if (basename(element.path).startsWith("log_")) {
          if (element
              .statSync()
              .modified
              .isBefore(DateTime.now().add(Duration(days: -7)))) {
            element.deleteSync();
          }
        }
      });
    } catch (e) {
      print(e);
    }
  }

  Future<void> initLoggerFilePath() async {
    packageInfo = await PackageInfo.fromPlatform();
    if (Platform.isMacOS) {
      tempDir = await getApplicationSupportDirectory();
    } else {
      tempDir =
          await getExternalStorageDirectory() ?? await getTemporaryDirectory();
    }
    logFile = File(
        "${tempDir.path}/log_${DateFormat("yyyy-MM-dd").format(DateTime.now())}.txt");
    cursorFile = File(
        "${tempDir.path}/log_${DateFormat("yyyy-MM-dd").format(DateTime.now())}_cursor.txt");

    if (!logFile.existsSync()) {
      logFile.create(recursive: true);
    }
    if (!cursorFile.existsSync()) {
      cursorFile.create(recursive: true);
      cursorFile.writeAsString("0");
    }
    print("日志地址\t${logFile.path}");
    return;
  }

  String generateSignature(String dataIn, signature) {
    var encodedKey = utf8.encode(signature); // signature=encryption key
    var hmacSha256 = new Hmac(sha256, encodedKey); // HMAC-SHA256 with key
    var bytesDataIn = utf8.encode(dataIn); // encode the data to Unicode.
    var digest = hmacSha256.convert(bytesDataIn); // encrypt target data
    String singedValue = digest.toString();
    return singedValue;
  }
}

class MyPrinter extends LogPrinter {
  static final levelPrefixes = {
    Level.verbose: '650',
    Level.debug: '100',
    Level.info: '200',
    Level.warning: '300',
    Level.error: '400',
    Level.wtf: '500',
  };

  PackageInfo packageInfo;

  String deviceId;

  MyPrinter({
    required this.packageInfo,
    required this.deviceId,
  });

  @override
  List<String> log(LogEvent event) {
    return [logFormat(event)];
  }

  String logFormat(LogEvent event) {
    if (event.message is String) {
      String? stackTraceStr;
      int methodCount = 1;
      if (event.stackTrace == null) {
        stackTraceStr = formatStackTrace(StackTrace.current, 3, 1);
      } else {
        stackTraceStr = formatStackTrace(event.stackTrace, 0, methodCount);
      }

      Map<String, dynamic> map = {
        'level': levelPrefixes[event.level]!,
        "message": "${event.message}",
        'context': {
          "timeStamp": DateTime.now().millisecondsSinceEpoch,
          "date": DateFormat("yyyy-MM-dd HH:mm:ss").format(DateTime.now()),
          "versionCode": packageInfo.buildNumber,
          "versionName": packageInfo.version,
          "userId": LogUtil.logUserId ?? "",
          "phone": LogUtil.logUserPhone ?? "",
          "deviceId": deviceId.hashCode.toString(),
          "os_type": Platform.operatingSystem,
          "error": event.error?.toString() ?? "",
          "stack": stackTraceStr ?? "",
        }
      };
      return json.encode(map);
    }
    return "";
  }

  String? formatStackTrace(StackTrace? stackTrace, int limit, int methodCount) {
    var lines = stackTrace.toString().split('\n');
    var formatted = <String>[];
    var count = 0;
    for (var line in lines) {
      if (line.isEmpty) {
        continue;
      }
      if (count <= limit) {
        count++;
        continue;
      }
      formatted.add('#$count   ${line.replaceFirst(RegExp(r'#\d+\s+'), '')}');
      if (++count >= methodCount) {
        break;
      }
    }

    if (formatted.isEmpty) {
      return null;
    } else {
      return formatted.join('\n');
    }
  }
}

class ConsoleOutput extends LogOutput {
  File logFile;
  final futures = <Future>[];
  final lock = new synchronized.Lock();

  ConsoleOutput(this.logFile);

  @override
  void output(OutputEvent event) {
    for (var line in event.lines) {
      print(line);
      futures.add(lock.synchronized(() => send(line)));
    }
  }

  Future send(String message) async {
    try {
      await logFile.writeAsString('$message\n',
          mode: FileMode.append, flush: true);
    } catch (e) {
      print("Error: $e");
    }
    return await logFile.length();
  }
}

/*
void doUploadLog() async {
  int lineNum = 0;
  int maxLine = 30;
  if (cursorFile.existsSync()) {
    lineNum = int.parse(await cursorFile.readAsString());
  }
  var list = await logFile.readAsLines();

  var logList = [];

  int currentLineNum = 0;
  for (int i = lineNum; i < min(lineNum + maxLine, list.length); i += 1) {
    try {
      var logObj = json.decode(list[i]);
      if (logObj["message"].toString().length > 1500) {
        ///避免消息体过长
        logObj["message"] = logObj["message"].toString().substring(0, 1500);
      }
      logList.add(logObj);
    } catch (e) {
      print(e);
    }
    currentLineNum = i;
  }

  lineNum = currentLineNum;

  if (logList.isNotEmpty) {
    var channel = "ty_reader_${Platform.isAndroid ? "android" : "iOS"}";
    var params = {
      "channel": channel,
      "logs": json.encode(logList),
    };

    var unSign = "";
    params.forEach((key, value) {
      unSign += key + "=" + value;
    });

    var sign = generateSignature(
        unSign, "ZTNlOTM2NTM3NzBiNDQ3ZDY2OGVmY2VlYWI1ZGFkYzg");

    Response result;
    try {
      result = await Dio().post(
        "https://api-logging.tengyue360.com/logger/multi",
        data: {
          'logs': json.encode(logList),
          'channel': channel,
          'sign': sign.toLowerCase(),
        },
        options: Options(
          contentType: "multipart/form-data",
        ),
      );

      if (result.data["code"] == 0) {
        print("日志上传成功");
        cursorFile.writeAsString((lineNum + 1).toString());
      } else {
        logger.i("上传日志失败 $result");
      }
    } catch (e) {
      logger.i("上传日志失败 $e");
    }
  }
  //10秒上传一次日志
  Timer(Duration(seconds: 10), () {
    doUploadLog();
  });
}*/
