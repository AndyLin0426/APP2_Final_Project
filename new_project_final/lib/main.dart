import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:path/path.dart';



void main() async{
  initializeDateFormatting('zh_CN', null).then((_) {

    runApp(MyApp());
  });
}
/// 初始化套件
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
FlutterLocalNotificationsPlugin();

///建一個Service類別來管理
class LocalNotificationService {

  ///第幾則通知
  var id = 0;

  Future<void> initialize() async {
    ///初始化在Android上的通知設定
    const AndroidInitializationSettings initializationSettingsAndroid =
    AndroidInitializationSettings('@mipmap/ic_launcher');

    ///設定組合
    final InitializationSettings initializationSettings =
    InitializationSettings(
      android: initializationSettingsAndroid,
    );

    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse:
          (NotificationResponse notificationResponse) {
        ///收到通知要做的事

      },

    );

  }

  ///跳出通知
  ///(自定的部份，如果你有用到Firebase來發送訊息，要和Firebase設定的一樣，不然不會有投頭顯示)
  Future<void> showNotification(String title,String body) async {
    const AndroidNotificationDetails androidNotificationDetails =
    AndroidNotificationDetails('新通知', '天氣警報',
        channelDescription: '天氣預報通知',
        importance: Importance.max,
        priority: Priority.high,
        ticker: 'ticker');
    const NotificationDetails notificationDetails =
    NotificationDetails(android: androidNotificationDetails);
    await flutterLocalNotificationsPlugin.show(
        id++, '$title', '$body', notificationDetails,
        payload: '要帶回程式的資料(如果有做點按後回到程式的功能)');
  }
}

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();
  static Database? _database;

  DatabaseHelper._privateConstructor();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    // Get a location using getDatabasesPath
    var databasesPath = await getDatabasesPath();
    String path = join(databasesPath, 'weather.db');

    // Create the database
    return await openDatabase(path, version: 1, onCreate: _createDatabase);
  }

  Future<void> _createDatabase(Database db, int version) async {
    // Create the table to store eight day weather forecast data
    await db.execute('''
      CREATE TABLE eight_day_weather (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        city TEXT,
        date TEXT,
        temperaturemin TEXT,
        temperaturemax  TEXT,
        humidity TEXT,
        weather_description TEXT,
        rain_probability TEXT
      )
    ''');
  }

  Future<void> insertEightDayWeather(List<Map<String, dynamic>> eightDayWeatherData, String city) async {
    deleteEightDayWeatherByCity(city);
    final Database db = await database;

    for (var weatherData in eightDayWeatherData) {

      Duration taiwanOffset = Duration(hours: 8);
      DateTime utcDateTime = DateTime.fromMillisecondsSinceEpoch(weatherData['dt'] * 1000, isUtc: true);
      DateTime taiwanDateTime = utcDateTime.add(taiwanOffset);

      String formattedTime = DateFormat('MM月dd號EEEE', 'zh_CN').format(taiwanDateTime);

      String rainpop = (weatherData['pop'] * 100).toString();
      int val = rainpop.indexOf(".", 0);

      if (val != -1) {
        rainpop = rainpop.substring(0, val);
      }
      await db.insert(
        'eight_day_weather',
        {
          'city': city,
          'date': formattedTime,
          'temperaturemin': weatherData['temp']['min'],
          'temperaturemax': weatherData['temp']['max'],
          'humidity': weatherData['humidity'],
          'weather_description': weatherData['weather'][0]['description'],
          'rain_probability': rainpop,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

    }

  }

  Future<List<Map<String, dynamic>>> getAllWeatherData(String city) async {
    final Database db = await database;
    // 根据城市名称查询表中对应城市的数据
    return await db.query('eight_day_weather', where: 'city = ?', whereArgs: [city]);
  }
  Future<void> deleteEightDayWeatherByCity(String city) async {
    final Database db = await database;
    await db.delete('eight_day_weather', where: 'city = ?', whereArgs: [city]);
    print('Deleted eight day weather data for $city');
  }

  Future<void> clearTable() async {
    final Database db = await database;
    await db.delete('eight_day_weather');
    print("Already Clear the Table");
  }
}



class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Weather App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: SplashScreen(),
    );
  }
}

class SplashScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    Timer(Duration(seconds: 2), () {
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => WeatherScreen()));
    });

    return Scaffold(
      body: Center(
        child: Text(
          'Weather App',
          style: TextStyle(fontSize: 24),
        ),
      ),
    );
  }
}

class WeatherScreen extends StatefulWidget {
  @override
  _WeatherScreenState createState() => _WeatherScreenState();
}

class _WeatherScreenState extends State<WeatherScreen> {
  final String apiKey = '5629b76d95f98a8b0c87061f003719f4';

  List<String> cities = [];
  final GlobalKey<_CityWeatherScreenState> _cityWeatherScreenStateKey = GlobalKey<_CityWeatherScreenState>();
  @override
  void initState() {
    super.initState();
    _updateWeatherForCities();
  }

  void _updateWeatherForCities() {
    int minute=0;
    int hour=0;
    int eightflash=1;
    int hourflash=1;

    Timer.periodic(Duration(seconds: 45), (timer) {

      if (DateTime.now().minute == 0  && eightflash == 1 && (DateTime.now().hour+8)==24) {

        _updateEightDayWeather();
        eightflash = 0;
      }
      if (DateTime.now().minute == 0 && hourflash == 1) {

        _updateHourlyWeather();
        hourflash = 0;
      }
      Timer.periodic(Duration(minutes: 5), (timer) {
        if(eightflash==0){
          eightflash=1;
        }
        if(hourflash==0){
          hourflash=1;
        }
      });
    });

    // Check for hourly weather updates at the beginning of each hour

  }

  void _updateHourlyWeather() {
    for (String city in cities) {
      _getWeather(city);

    }
  }

  void _updateEightDayWeather() async {
    for (String city in cities) {

      var cityLocation = await getCityLocation(city);
      double? latitude = cityLocation?.latitude;
      double? longitude = cityLocation?.longitude;
      DateTime now = DateTime.now();

      // 获取当前时间的 Unix 时间戳（以秒为单位）
      int unixTimestamp = now.millisecondsSinceEpoch ~/ 1000;

      var weatherAPIUrl =
          'https://api.openweathermap.org/data/3.0/onecall?lat=$latitude&lon=$longitude&dt=$unixTimestamp&exclude=current,minutely&lang=zh_tw&units=metric&appid=$apiKey';

      var response = await http.get(Uri.parse(weatherAPIUrl));
      if (response.statusCode == 200) {
        final decodedResponse = json.decode(response.body);
        List<dynamic> eightDayWeatherData = decodedResponse["daily"];
        // 存儲到資料庫中
        _saveEightDayWeatherToDatabase(eightDayWeatherData,city);
      } else {
        throw Exception('Failed to load weather data');
      }
    }
  }

  Future<void> _getWeather(String city) async {

    var weatherAPIUrl='https://opendata.cwa.gov.tw/api/v1/rest/datastore/F-C0032-001?Authorization=CWA-9196D8BF-9B11-4F95-A8B5-C4CB32D5F1A5&elementName=PoP,MaxT,MinT,';

    var response = await http.get(Uri.parse(weatherAPIUrl));
    double pop=0,minT=0,maxT=0;
    if (response.statusCode == 200) {
      final decodedResponse = json.decode(response.body);
      for(int i=0;i<22;i++){
        String str='';
        if(decodedResponse["records"]["location"][i]["locationName"]==city){
          pop=double.parse(decodedResponse["records"]["location"][i]["weatherElement"][0]["time"][0]["parameter"]["parameterName"]);
          minT=double.parse(decodedResponse["records"]["location"][i]["weatherElement"][1]["time"][0]["parameter"]["parameterName"]);
          maxT=double.parse(decodedResponse["records"]["location"][i]["weatherElement"][2]["time"][0]["parameter"]["parameterName"]);

          LocalNotificationService().showNotification("未來6小時天氣速報","$city於接下來六個小時內最高溫：$maxT度、最低溫：$minT、降雨機率：$pop%");
          if(maxT>=32.0){
            LocalNotificationService().showNotification("高溫通報","$city於接下來六個小時內氣溫超過36度，請注意防曬");
          }
          if(minT<=10.0){
            LocalNotificationService().showNotification("低溫通報","$city於接下來六個小時內氣溫低於10度，請注意保暖");
          }
          if(pop>=50.0) {
            LocalNotificationService().showNotification("下雨通報", "$city於接下來六個小時內可能會下雨，請注意安全並攜帶雨具");
          }
        }
        await Future.delayed(Duration(seconds: 1));
      }
      //WeatherData=decodedResponse["records"]["location"][3]["locationName"];

      //print(WeatherData);
    }


    setState(() {

    });
  }







  Future<void> _saveEightDayWeatherToDatabase(List<dynamic> eightDayWeatherData,city) async {

    await DatabaseHelper.instance.insertEightDayWeather(
      eightDayWeatherData.map<Map<String, dynamic>>((e) => e as Map<String, dynamic>).toList(),
      city,
    );
  }

  Future<void> _showCitySelectionDialog(BuildContext context) async {
    String? city = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('選擇城市'),
          content: DropdownButton<String>(
            items: <String>[
              '臺北市',
              '新北市',
              '桃園市',
              '臺中市',
              '臺南市',
              '高雄市',
              '基隆市',
              '新竹市',
              '新竹縣',
              '嘉義市',
              '嘉義縣',
              '宜蘭縣',
              '苗栗縣',
              '彰化縣',
              '南投縣',
              '雲林縣',
              '屏東縣',
              '臺東縣',
              '花蓮縣',
              '澎湖縣',
              '金門縣',
              '連江縣'
            ].map((String value) {
              return DropdownMenuItem<String>(
                value: value,
                child: Text(value),
              );
            }).toList(),
            onChanged: (String? newValue) {
              if (newValue != null && cities.contains(newValue)) {
                // 如果城市已存在，彈出提示
                showDialog(
                  context: context,
                  builder: (BuildContext context) {
                    return AlertDialog(
                      title: Text('城市已存在'),
                      content: Text('選擇的城市已經存在於列表中。'),
                      actions: <Widget>[
                        TextButton(
                          child: Text('確定'),
                          onPressed: () {
                            Navigator.of(context).pop();
                          },
                        ),
                      ],
                    );
                  },
                );
              } else if (newValue != null) {
                // 添加城市到列表中
                Navigator.of(context).pop(newValue);
              }
            },
          ),
        );
      },
    );

    if (city != null) {
      setState(() {
        cities.add(city);
      });
      print("get");
      _getWeather(city);
    }
  }

  Future<Location?> getCityLocation(String cityName) async {
    try {
      List<Location> locations = await locationFromAddress(cityName);
      if (locations.isNotEmpty) {
        return locations[0];
      } else {
        return null;
      }
    } catch (e) {
      print('Error fetching city location: $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Weather App'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            ElevatedButton(
              onPressed: () async {
                await _showCitySelectionDialog(context);
              },
              child: Text('新增城市'),
            ),
            SizedBox(height: 20),
            Expanded(
              child: GridView.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 1,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 5, // 調整卡片高度的寬高比
                ),
                itemCount: cities.length,
                itemBuilder: (context, index) {
                  String city = cities.elementAt(index);
                  return GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => CityWeatherScreen(city: city),
                        ),
                      );
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.blue, // 設置卡片顏色
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Expanded( // 使用Expanded以填滿剩餘的空間，確保Icon位於右側
                            child: Text(
                              city,
                              style: TextStyle(
                                color: Colors.white, // 設置文字顏色
                                fontSize: 20, // 增加字體大小
                              ),
                              textAlign: TextAlign.center, // 將文字置中
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.delete, color: Colors.white),
                            onPressed: () {
                              setState(() {
                                cities.removeAt(index);
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CityWeatherScreen extends StatefulWidget {
  final String city;

  CityWeatherScreen({required this.city});

  @override
  _CityWeatherScreenState createState() => _CityWeatherScreenState();
}

class _CityWeatherScreenState extends State<CityWeatherScreen> {
  late List<dynamic> hourlyWeatherData = [];

  Map<String, List<dynamic>> hourlyWeatherCache = {};

  @override
  void initState() {
    super.initState();
    //print("5466");
    _getWeather(widget.city);
  }
  Future<List<dynamic>> _returnhourlyWeatherData(){
    return Future.value(hourlyWeatherData);
  }

  Future<void> _getWeather(String city) async {
    var cityLocation = await getCityLocation(city);
    double? latitude = cityLocation?.latitude;
    double? longitude = cityLocation?.longitude;
    DateTime now = DateTime.now();

    // 获取当前时间的 Unix 时间戳（以秒为单位）
    int unixTimestamp = now.millisecondsSinceEpoch ~/ 1000;
    var weatherAPIUrl =
        'https://api.openweathermap.org/data/3.0/onecall?lat=$latitude&lon=$longitude&dt=$unixTimestamp&exclude=current,minutely&lang=zh_tw&units=metric&appid=5629b76d95f98a8b0c87061f003719f4';
    var response = await http.get(Uri.parse(weatherAPIUrl));
    print(weatherAPIUrl);
    if (response.statusCode == 200) {

      final decodedResponse = json.decode(response.body);
      List<dynamic> eightDayWeatherData = decodedResponse["daily"];
      // 存儲到資料庫中
      _WeatherScreenState wh=_WeatherScreenState();
      wh._saveEightDayWeatherToDatabase(eightDayWeatherData, city);
      //print(decodedResponse);
      //print("0000");
      setState(() {
        hourlyWeatherData = decodedResponse["hourly"].take(12).toList();
      });

      // Check weather conditions and send notifications

    } else {
      throw Exception('Failed to load weather data');
    }
  }


  Future<Location?> getCityLocation(String cityName) async {
    try {
      List<Location> locations = await locationFromAddress(cityName);
      if (locations.isNotEmpty) {
        return locations[0];
      } else {
        return null;
      }
    } catch (e) {
      print('Error fetching city location: $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Weather in ${widget.city}'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              ' ${widget.city}的每小時天氣預報',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 20),
            Expanded(
              child: ListView.builder(
                itemCount: hourlyWeatherData.length,
                itemBuilder: (context, index) {

                  var weatherData = hourlyWeatherData[index];

                  Duration taiwanOffset = Duration(hours: 8);
                  DateTime utcDateTime = DateTime.fromMillisecondsSinceEpoch(weatherData['dt'] * 1000, isUtc: true);
                  DateTime taiwanDateTime = utcDateTime.add(taiwanOffset);
                  String formattedTime = DateFormat.Hm().format(taiwanDateTime);

                  var temperature = weatherData['temp'];
                  var humidity = weatherData['humidity'];
                  var weatherDescription = weatherData['weather'][0]['description'];
                  String rainpop = (weatherData['pop'] * 100).toString();
                  int val = rainpop.indexOf(".", 0);

                  if (val != -1) {
                    rainpop = rainpop.substring(0, val);
                  }

                  return Card(
                    child: ListTile(
                      title: Text('時間: ${formattedTime}'),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('氣溫: $temperature°C'),
                          Text('濕度: $humidity%'),
                          Text('天氣狀況: $weatherDescription'),
                          Text('降雨機率: $rainpop%'),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => EightDayWeatherScreen(city: widget.city),
                  ),
                );
              },
              child: Text('查看八天天氣預報'),
            ),
          ],
        ),
      ),
    );
  }
}

class EightDayWeatherScreen extends StatefulWidget {
  final String city;

  EightDayWeatherScreen({required this.city});

  @override
  _EightDayWeatherScreenState createState() => _EightDayWeatherScreenState();
}

class _EightDayWeatherScreenState extends State<EightDayWeatherScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Eight Day Weather Forecast'),
      ),
      body: Center(
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: DatabaseHelper.instance.getAllWeatherData(widget.city),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return CircularProgressIndicator();
            } else if (snapshot.hasError) {
              return Text('Error: ${snapshot.error}');
            } else {
              List<Map<String, dynamic>> weatherData = snapshot.data ?? [];
              return ListView.builder(
                itemCount: weatherData.length,
                itemBuilder: (context, index) {
                  var data = weatherData[index];
                  return Card(
                    child: ListTile(
                      title: Text('日期: ${data['date']}'),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('最低氣溫: ${data['temperaturemin']}°C'),
                          Text('最高氣溫: ${data['temperaturemax']}°C'),
                          Text('濕度: ${data['humidity']}%'),
                          Text('天氣狀況: ${data['weather_description']}'),
                          Text('降雨機率: ${data['rain_probability']}%'),
                        ],
                      ),
                    ),
                  );
                },
              );
            }
          },
        ),
      ),
    );
  }
}