import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import 'firebase_options.dart';

// Configuração de notificações
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
FlutterLocalNotificationsPlugin();

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print("Handling a background message: ${message.messageId}");
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Configurar notificações
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  const AndroidInitializationSettings initializationSettingsAndroid =
  AndroidInitializationSettings('@mipmap/ic_launcher');

  final InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
  );

  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  FirebaseMessaging messaging = FirebaseMessaging.instance;
  NotificationSettings settings = await messaging.requestPermission();
  print('User granted permission: ${settings.authorizationStatus}');

  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    print('Got a message whilst in the foreground!');
    print('Message data: ${message.data}');

    if (message.notification != null) {
      showNotification(
        title: message.notification!.title!,
        body: message.notification!.body!,
      );
    }
  });

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProvider(create: (_) => AgendaService()),
      ],
      child: const MyApp(),
    ),
  );
}

void showNotification({required String title, required String body}) async {
  const AndroidNotificationDetails androidPlatformChannelSpecifics =
  AndroidNotificationDetails(
    'high_importance_channel',
    'High Importance Notifications',
    importance: Importance.max,
    priority: Priority.high,
    showWhen: false,
  );

  const NotificationDetails platformChannelSpecifics =
  NotificationDetails(android: androidPlatformChannelSpecifics);

  await flutterLocalNotificationsPlugin.show(
    0,
    title,
    body,
    platformChannelSpecifics,
    payload: 'item x',
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Agenda do Pedreiro',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const AuthWrapper(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context);

    if (auth.user == null) {
      return const LoginScreen();
    }

    if (auth.user!.email == 'tradetoolproject@gmail.com') {
      return const PedreiroDashboard();
    }

    return const ClienteDashboard();
  }
}

// Serviços e Modelos
class AuthService with ChangeNotifier {
  User? _user;
  String? _userName;
  String? _userEmail;

  User? get user => _user;
  String? get userName => _userName;
  String? get userEmail => _userEmail;

  AuthService() {
    _setupAuthListener();
  }

  void _setupAuthListener() {
    FirebaseAuth.instance.authStateChanges().listen((User? user) {
      _user = user;
      if (user != null) {
        _loadUserData();
      }
      notifyListeners();
    });
  }

  Future<void> _loadUserData() async {
    if (_user != null) {
      final doc = await FirebaseFirestore.instance
          .collection('clientes')
          .doc(_user!.uid)
          .get();

      if (doc.exists) {
        _userName = doc['nome'];
        _userEmail = doc['email'];
      }
    }
    notifyListeners();
  }

  Future<void> login(String email, String password) async {
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      throw Exception(e.message);
    }
  }

  Future<void> register(String email, String password, String name) async {
    try {
      await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      // Salvar nome do cliente no Firestore
      await FirebaseFirestore.instance
          .collection('clientes')
          .doc(FirebaseAuth.instance.currentUser!.uid)
          .set({
        'nome': name,
        'email': email,
      });
      _userName = name;
      _userEmail = email;
    } on FirebaseAuthException catch (e) {
      throw Exception(e.message);
    }
  }

  Future<void> logout() async {
    await FirebaseAuth.instance.signOut();
    _userName = null;
    _userEmail = null;
  }
}

class AgendaService with ChangeNotifier {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  List<Servico> _servicos = [];
  List<Agendamento> _agendamentos = [];
  List<HorarioTrabalho> _horariosTrabalho = [];
  List<DateTime> _horariosBloqueados = [];

  List<Servico> get servicos => _servicos;
  List<Agendamento> get agendamentos => _agendamentos;
  List<HorarioTrabalho> get horariosTrabalho => _horariosTrabalho;
  List<DateTime> get horariosBloqueados => _horariosBloqueados;

  AgendaService() {
    _carregarDados();
  }

  Future<void> _carregarDados() async {
    await _carregarServicos();
    await _carregarAgendamentos();
    await _carregarHorariosTrabalho();
    await _carregarHorariosBloqueados();
  }

  Future<void> _carregarServicos() async {
    final snapshot = await _db.collection('servicos').get();
    _servicos = snapshot.docs.map((doc) {
      final data = doc.data();
      return Servico(
        id: doc.id,
        nome: data['nome'] ?? '',
        valor: (data['valor'] as num).toDouble(),
        duracao: (data['duracao'] as num?)?.toInt() ?? 60, // Default 60 minutos
      );
    }).toList();
    notifyListeners();
  }

  Future<void> _carregarAgendamentos() async {
    final snapshot = await _db.collection('agendamentos').get();
    _agendamentos = snapshot.docs
        .map((doc) => Agendamento.fromMap(doc.data(), doc.id))
        .toList();
    notifyListeners();
  }

  Future<void> _carregarHorariosTrabalho() async {
    final snapshot = await _db.collection('horarios_trabalho').get();
    _horariosTrabalho = snapshot.docs.map((doc) {
      final data = doc.data();
      return HorarioTrabalho(
        id: doc.id,
        dia: data['dia'] as int?,
        inicio: data['inicio'] as String,
        fim: data['fim'] as String,
        dataEspecifica: data['data_especifica'] != null
            ? (data['data_especifica'] as Timestamp).toDate()
            : null,
      );
    }).toList();
    notifyListeners();
  }

  Future<void> _carregarHorariosBloqueados() async {
    final snapshot = await _db.collection('horarios_bloqueados').get();
    _horariosBloqueados = snapshot.docs
        .map((doc) => (doc['data'] as Timestamp).toDate())
        .toList();
    notifyListeners();
  }

  Future<void> adicionarServico(String nome, double valor, int duracao) async {
    await _db.collection('servicos').add({
      'nome': nome,
      'valor': valor,
      'duracao': duracao,
    });
    await _carregarServicos();
  }

  Future<void> adicionarAgendamento(Agendamento agendamento) async {
    await _db.collection('agendamentos').add({
      'clienteId': agendamento.clienteId,
      'clienteNome': agendamento.clienteNome,
      'clienteEmail': agendamento.clienteEmail,
      'servicos': agendamento.servicos.map((s) => s.toMap()).toList(),
      'data': Timestamp.fromDate(agendamento.data),
      'horario': agendamento.horario,
      'status': agendamento.status,
    });
    await _carregarAgendamentos();
  }

  Future<void> atualizarStatusAgendamento(String id, String status) async {
    await _db.collection('agendamentos').doc(id).update({'status': status});
    await _carregarAgendamentos();
  }

  Future<void> atualizarAgendamento(Agendamento agendamento) async {
    await _db.collection('agendamentos').doc(agendamento.id).update({
      'servicos': agendamento.servicos.map((s) => s.toMap()).toList(),
      'data': Timestamp.fromDate(agendamento.data),
      'horario': agendamento.horario,
    });
    await _carregarAgendamentos();
  }

  Future<void> cancelarAgendamento(String id, String motivo) async {
    await _db.collection('agendamentos').doc(id).update({
      'status': 'Cancelado',
      'motivo_cancelamento': motivo,
    });
    await _carregarAgendamentos();
  }

  Future<void> bloquearHorario(DateTime data) async {
    await _db.collection('horarios_bloqueados').add({'data': Timestamp.fromDate(data)});
    await _carregarHorariosBloqueados();
  }

  Future<void> desbloquearHorario(DateTime data) async {
    final snapshot = await _db.collection('horarios_bloqueados')
        .where('data', isEqualTo: Timestamp.fromDate(data))
        .get();

    for (var doc in snapshot.docs) {
      await doc.reference.delete();
    }

    await _carregarHorariosBloqueados();
  }

  Future<void> adicionarHorarioTrabalho(HorarioTrabalho horario) async {
    await _db.collection('horarios_trabalho').add({
      'dia': horario.dia,
      'inicio': horario.inicio,
      'fim': horario.fim,
      'data_especifica': horario.dataEspecifica != null
          ? Timestamp.fromDate(horario.dataEspecifica!)
          : null,
    });
    await _carregarHorariosTrabalho();
  }

  Future<void> removerHorarioTrabalho(String id) async {
    await _db.collection('horarios_trabalho').doc(id).delete();
    await _carregarHorariosTrabalho();
  }

  // Gerar slots disponíveis considerando duração do serviço e horários de trabalho
  List<String> gerarSlotsDisponiveis(DateTime data, int duracaoServico) {
    final List<String> todosHorarios = [
      '08:00', '09:00', '10:00', '11:00', '12:00',
      '13:00', '14:00', '15:00', '16:00', '17:00'
    ];

    final List<String> disponiveis = [];

    // 1. Verificar horários de trabalho
    final diaSemana = data.weekday;
    final horariosDia = _horariosTrabalho.where((h) {
      if (h.dataEspecifica != null) {
        return isSameDay(h.dataEspecifica, data);
      }
      return h.dia == diaSemana;
    }).toList();

    if (horariosDia.isEmpty) return []; // Dia sem trabalho

    // 2. Converter horários para DateTime
    final horaInicio = horariosDia.map((h) {
      final partes = h.inicio.split(':');
      return DateTime(data.year, data.month, data.day, int.parse(partes[0]), int.parse(partes[1]));
    }).reduce((a, b) => a.isBefore(b) ? a : b);

    final horaFim = horariosDia.map((h) {
      final partes = h.fim.split(':');
      return DateTime(data.year, data.month, data.day, int.parse(partes[0]), int.parse(partes[1]));
    }).reduce((a, b) => a.isAfter(b) ? a : b);

    // 3. Gerar slots considerando duração
    DateTime slotAtual = horaInicio;
    while (slotAtual.add(Duration(minutes: duracaoServico)).isBefore(horaFim) ||
        slotAtual.add(Duration(minutes: duracaoServico)).isAtSameMomentAs(horaFim)) {

      final horarioStr = '${slotAtual.hour.toString().padLeft(2, '0')}:${slotAtual.minute.toString().padLeft(2, '0')}';

      // 4. Verificar se não está bloqueado
      final estaBloqueado = _horariosBloqueados.any((hb) =>
      hb.year == data.year &&
          hb.month == data.month &&
          hb.day == data.day &&
          hb.hour == slotAtual.hour &&
          hb.minute == slotAtual.minute);

      // 5. Verificar se não conflita com outro agendamento
      final conflitoAgendamento = _agendamentos.any((ag) {
        if (!isSameDay(ag.data, data)) return false;

        final partes = ag.horario.split(':');
        final horaAg = int.parse(partes[0]);
        final minAg = int.parse(partes[1]);
        final inicioAg = DateTime(data.year, data.month, data.day, horaAg, minAg);
        final fimAg = inicioAg.add(Duration(minutes: ag.duracaoTotal));

        final fimSlot = slotAtual.add(Duration(minutes: duracaoServico));

        return (slotAtual.isBefore(fimAg) && fimSlot.isAfter(inicioAg));
      });

      if (!estaBloqueado && !conflitoAgendamento) {
        disponiveis.add(horarioStr);
      }

      slotAtual = slotAtual.add(const Duration(minutes: 30));
    }

    return disponiveis;
  }
}

class Servico {
  final String id;
  final String nome;
  final double valor;
  final int duracao; // em minutos

  Servico({
    required this.id,
    required this.nome,
    required this.valor,
    required this.duracao,
  });

  factory Servico.fromMap(Map<String, dynamic> map) {
    return Servico(
      id: map['id'] ?? '',
      nome: map['nome'] ?? '',
      valor: (map['valor'] as num).toDouble(),
      duracao: (map['duracao'] as num).toInt(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nome': nome,
      'valor': valor,
      'duracao': duracao,
    };
  }
}

class Agendamento {
  final String id;
  final String clienteId;
  final String clienteNome;
  final String clienteEmail;
  List<Servico> servicos;
  DateTime data;
  String horario;
  String status;
  String? motivoCancelamento;

  Agendamento({
    required this.id,
    required this.clienteId,
    required this.clienteNome,
    required this.clienteEmail,
    required this.servicos,
    required this.data,
    required this.horario,
    this.status = 'Pendente',
    this.motivoCancelamento,
  });

  factory Agendamento.fromMap(Map<String, dynamic> map, String docId) {
    return Agendamento(
      id: docId,
      clienteId: map['clienteId'] ?? '',
      clienteNome: map['clienteNome'] ?? '',
      clienteEmail: map['clienteEmail'] ?? '',
      servicos: (map['servicos'] as List<dynamic>)
          .map((s) => Servico.fromMap(s))
          .toList(),
      data: (map['data'] as Timestamp).toDate(),
      horario: map['horario'] ?? '',
      status: map['status'] ?? 'Pendente',
      motivoCancelamento: map['motivo_cancelamento'],
    );
  }

  int get duracaoTotal {
    return servicos.fold(0, (sum, servico) => sum + servico.duracao);
  }

  double get valorTotal {
    return servicos.fold(0, (sum, servico) => sum + servico.valor);
  }
}

class HorarioTrabalho {
  final String id;
  final int? dia; // 1-7 (segunda a domingo)
  final String inicio;
  final String fim;
  final DateTime? dataEspecifica; // para dias específicos

  HorarioTrabalho({
    required this.id,
    this.dia,
    required this.inicio,
    required this.fim,
    this.dataEspecifica,
  });

  factory HorarioTrabalho.fromMap(Map<String, dynamic> map, String docId) {
    return HorarioTrabalho(
      id: docId,
      dia: map['dia'] as int?,
      inicio: map['inicio'] as String,
      fim: map['fim'] as String,
      dataEspecifica: map['data_especifica'] != null
          ? (map['data_especifica'] as Timestamp).toDate()
          : null,
    );
  }
}

// Telas
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController(text: 'tradetoolproject@gmail.com');
  final _passwordController = TextEditingController(text: '');
  bool _isRegistering = false;
  final _nameController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_isRegistering)
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Nome completo'),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Por favor, insira o nome';
                    }
                    return null;
                  },
                ),
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(labelText: 'Email'),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Por favor, insira o email';
                  }
                  return null;
                },
              ),
              TextFormField(
                controller: _passwordController,
                decoration: const InputDecoration(labelText: 'Senha'),
                obscureText: true,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Por favor, insira a senha';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () async {
                  if (_formKey.currentState!.validate()) {
                    try {
                      if (_isRegistering) {
                        await Provider.of<AuthService>(context, listen: false).register(
                          _emailController.text,
                          _passwordController.text,
                          _nameController.text,
                        );
                      } else {
                        await Provider.of<AuthService>(context, listen: false).login(
                          _emailController.text,
                          _passwordController.text,
                        );
                      }
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Erro: $e')),
                      );
                    }
                  }
                },
                child: Text(_isRegistering ? 'Registrar' : 'Entrar'),
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    _isRegistering = !_isRegistering;
                  });
                },
                child: Text(_isRegistering
                    ? 'Já tem conta? Faça login'
                    : 'Criar nova conta'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PedreiroDashboard extends StatefulWidget {
  const PedreiroDashboard({super.key});

  @override
  State<PedreiroDashboard> createState() => _PedreiroDashboardState();
}

class _PedreiroDashboardState extends State<PedreiroDashboard> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  int _currentIndex = 0;
  List<DateTime> _selectedDays = [];
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    Provider.of<AgendaService>(context, listen: false)._carregarDados();
  }

  void _onDaySelected(DateTime selectedDay, DateTime focusedDay) {
    setState(() {
      _selectedDay = selectedDay;
      _focusedDay = focusedDay;

      // Adicionar/remover dia selecionado
      if (_selectedDays.any((day) => isSameDay(day, selectedDay))) {
        _selectedDays.removeWhere((day) => isSameDay(day, selectedDay));
      } else {
        _selectedDays.add(selectedDay);
      }
    });
  }

  Future<void> _saveWorkingHours() async {
    if (_startTime == null || _endTime == null || _selectedDays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione horários e dias')),
      );
      return;
    }

    final agendaService = Provider.of<AgendaService>(context, listen: false);

    for (final day in _selectedDays) {
      await agendaService.adicionarHorarioTrabalho(HorarioTrabalho(
        id: '',
        dataEspecifica: day,
        inicio: '${_startTime!.hour}:${_startTime!.minute}',
        fim: '${_endTime!.hour}:${_endTime!.minute}',
      ));
    }

    setState(() {
      _selectedDays.clear();
      _startTime = null;
      _endTime = null;
    });
  }


  @override
  Widget build(BuildContext context) {
    final agendaService = Provider.of<AgendaService>(context);
    final authService = Provider.of<AuthService>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Painel do Pedreiro'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => authService.logout(),
          ),
        ],
      ),
      body: _currentIndex == 0
          ? _buildAgenda(agendaService)
          : _buildHorariosTrabalho(agendaService),
      floatingActionButton: _currentIndex == 0
          ? FloatingActionButton(
        onPressed: () => _showAdicionarServicoDialog(context),
        child: const Icon(Icons.add),
      )
          : FloatingActionButton(
        onPressed: () => _showAdicionarHorarioDialog(context),
        child: const Icon(Icons.add),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_today),
            label: 'Agenda',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.schedule),
            label: 'Horários',
          ),
        ],
      ),
    );
  }

  Widget _buildAgenda(AgendaService agendaService) {
    return Column(
      children: [
        TableCalendar(
          firstDay: DateTime.now(),
          lastDay: DateTime.now().add(const Duration(days: 365)),
          focusedDay: _focusedDay,
          selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
          onDaySelected: (selectedDay, focusedDay) {
            setState(() {
              _selectedDay = selectedDay;
              _focusedDay = focusedDay;
            });
          },
          eventLoader: (day) {
            return agendaService.agendamentos
                .where((ag) => isSameDay(ag.data, day))
                .toList();
          },
        ),
        const SizedBox(height: 10),
        Expanded(
          child: _buildAgendamentosDoDia(agendaService, _selectedDay!),
        ),
      ],
    );
  }

  Widget _buildHorariosTrabalho(AgendaService agendaService) {
    return ListView.builder(
      itemCount: agendaService.horariosTrabalho.length,
      itemBuilder: (context, index) {
        final horario = agendaService.horariosTrabalho[index];
        return Card(
          margin: const EdgeInsets.all(8),
          child: ListTile(
            title: Text(horario.dataEspecifica != null
                ? 'Horário específico: ${DateFormat('dd/MM/yyyy').format(horario.dataEspecifica!)}'
                : 'Dia da semana: ${_diaSemana(horario.dia)}'),
            subtitle: Text('${horario.inicio} - ${horario.fim}'),
            trailing: IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () => agendaService.removerHorarioTrabalho(horario.id),
            ),
          ),
        );
      },
    );
  }

  String _diaSemana(int? dia) {
    switch (dia) {
      case 1: return 'Segunda-feira';
      case 2: return 'Terça-feira';
      case 3: return 'Quarta-feira';
      case 4: return 'Quinta-feira';
      case 5: return 'Sexta-feira';
      case 6: return 'Sábado';
      case 7: return 'Domingo';
      default: return 'Dia específico';
    }
  }

  Widget _buildAgendamentosDoDia(AgendaService agendaService, DateTime dia) {
    final agendamentosDoDia = agendaService.agendamentos
        .where((ag) => isSameDay(ag.data, dia))
        .toList();

    if (agendamentosDoDia.isEmpty) {
      return const Center(child: Text('Nenhum agendamento para este dia'));
    }

    return ListView.builder(
      itemCount: agendamentosDoDia.length,
      itemBuilder: (context, index) {
        final ag = agendamentosDoDia[index];
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
          child: ListTile(
            title: Text(ag.clienteNome),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var servico in ag.servicos)
                  Text('• ${servico.nome} - ${servico.duracao}min - R\$${servico.valor.toStringAsFixed(2)}'),
                Text('${DateFormat('dd/MM/yyyy').format(ag.data)} - ${ag.horario}'),
                Text('Duração total: ${ag.duracaoTotal}min'),
                Text('Total: R\$${ag.valorTotal.toStringAsFixed(2)}'),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (ag.status == 'Pendente')
                  IconButton(
                    icon: const Icon(Icons.check, color: Colors.green),
                    onPressed: () {
                      agendaService.atualizarStatusAgendamento(ag.id, 'Aprovado');
                      // Enviar notificação ao cliente
                      showNotification(
                        title: 'Agendamento Aprovado!',
                        body: 'Seu agendamento para ${ag.servicos.first.nome} foi aprovado',
                      );
                    },
                  ),
                if (ag.status == 'Pendente')
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.red),
                    onPressed: () => _rejeitarAgendamento(ag),
                  ),
                if (ag.status != 'Cancelado')
                  IconButton(
                    icon: const Icon(Icons.cancel, color: Colors.orange),
                    onPressed: () => _cancelarAgendamento(ag),
                  ),
                Chip(
                  label: Text(ag.status),
                  backgroundColor: ag.status == 'Aprovado'
                      ? Colors.green[100]
                      : ag.status == 'Rejeitado'
                      ? Colors.red[100]
                      : ag.status == 'Cancelado'
                      ? Colors.orange[100]
                      : Colors.blue[100],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _rejeitarAgendamento(Agendamento ag) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Motivo da Rejeição'),
        content: TextField(
          controller: TextEditingController(),
          decoration: const InputDecoration(hintText: 'Digite o motivo da rejeição'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              Provider.of<AgendaService>(context, listen: false)
                  .atualizarStatusAgendamento(ag.id, 'Rejeitado');
              Navigator.pop(context);

              // Enviar notificação ao cliente
              showNotification(
                title: 'Agendamento Rejeitado',
                body: 'Seu agendamento para ${ag.servicos.first.nome} foi rejeitado',
              );
            },
            child: const Text('Rejeitar'),
          ),
        ],
      ),
    );
  }

  void _cancelarAgendamento(Agendamento ag) {
    final motivoController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancelar Agendamento'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Tem certeza que deseja cancelar este agendamento?'),
            const SizedBox(height: 16),
            TextField(
              controller: motivoController,
              decoration: const InputDecoration(
                labelText: 'Motivo do cancelamento',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Voltar'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (motivoController.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Por favor, informe o motivo')),
                );
                return;
              }

              await Provider.of<AgendaService>(context, listen: false)
                  .cancelarAgendamento(ag.id, motivoController.text);

              Navigator.pop(context);

              // Enviar notificação ao cliente
              showNotification(
                title: 'Agendamento Cancelado',
                body: 'Seu agendamento para ${ag.servicos.first.nome} foi cancelado',
              );

              // Enviar email (seria feito via Cloud Function na prática)
              print('Enviar email para ${ag.clienteEmail} sobre cancelamento');
            },
            child: const Text('Confirmar Cancelamento'),
          ),
        ],
      ),
    );
  }

  void _showAdicionarServicoDialog(BuildContext context) {
    final nomeController = TextEditingController();
    final valorController = TextEditingController();
    final duracaoController = TextEditingController(text: '60');

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Adicionar Serviço'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nomeController,
                decoration: const InputDecoration(labelText: 'Nome do Serviço'),
              ),
              TextField(
                controller: valorController,
                decoration: const InputDecoration(labelText: 'Valor (R\$)'),
                keyboardType: TextInputType.number,
              ),
              TextField(
                controller: duracaoController,
                decoration: const InputDecoration(labelText: 'Duração (minutos)'),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                if (nomeController.text.isNotEmpty &&
                    valorController.text.isNotEmpty &&
                    duracaoController.text.isNotEmpty) {
                  Provider.of<AgendaService>(context, listen: false).adicionarServico(
                    nomeController.text,
                    double.parse(valorController.text),
                    int.parse(duracaoController.text),
                  );
                  Navigator.pop(context);
                }
              },
              child: const Text('Adicionar'),
            ),
          ],
        );
      },
    );
  }

  Future _showAdicionarHorarioDialog(BuildContext context) {
    int? selectedDay;
    TimeOfDay? startTime;
    TimeOfDay? endTime;
    DateTime? specificDate;

    final dayOptions = {
      1: 'Segunda-feira',
      2: 'Terça-feira',
      3: 'Quarta-feira',
      4: 'Quinta-feira',
      5: 'Sexta-feira',
      6: 'Sábado',
      7: 'Domingo',
      null: 'Data específica'
    };

    return showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Adicionar Horário de Trabalho'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButton<int?>(
                      value: selectedDay,
                      hint: const Text('Selecione o dia'),
                      items: dayOptions.entries.map((e) {
                        return DropdownMenuItem<int?>(
                          value: e.key,
                          child: Text(e.value),
                        );
                      }).toList(),
                      onChanged: (value) => setState(() => selectedDay = value),
                    ),

                    if (selectedDay == null)
                      TextButton(
                        onPressed: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: DateTime.now(),
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(const Duration(days: 365)),
                          );
                          if (date != null) {
                            setState(() => specificDate = date);
                          }
                        },
                        child: Text(
                          specificDate != null
                              ? 'Data: ${DateFormat('dd/MM/yyyy').format(specificDate!)}'
                              : 'Selecione uma data específica',
                        ),
                      ),

                    TextButton(
                      onPressed: () async {
                        final time = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay.now(),
                        );
                        if (time != null) {
                          setState(() => startTime = time);
                        }
                      },
                      child: Text(
                        startTime != null
                            ? 'Início: ${startTime!.format(context)}'
                            : 'Selecione o horário de início',
                      ),
                    ),

                    TextButton(
                      onPressed: () async {
                        final time = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay.now(),
                        );
                        if (time != null) {
                          setState(() => endTime = time);
                        }
                      },
                      child: Text(
                        endTime != null
                            ? 'Fim: ${endTime!.format(context)}'
                            : 'Selecione o horário de fim',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (startTime == null || endTime == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Preencha todos os campos')),
                      );
                      return;
                    }

                    if (selectedDay == null && specificDate == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Selecione uma data')),
                      );
                      return;
                    }

                    final inicioStr = '${startTime!.hour.toString().padLeft(2, '0')}:${startTime!.minute.toString().padLeft(2, '0')}';
                    final fimStr = '${endTime!.hour.toString().padLeft(2, '0')}:${endTime!.minute.toString().padLeft(2, '0')}';

                    Provider.of<AgendaService>(context, listen: false)
                        .adicionarHorarioTrabalho(HorarioTrabalho(
                      id: '',
                      dia: selectedDay,
                      inicio: inicioStr,
                      fim: fimStr,
                      dataEspecifica: specificDate,
                    ));

                    Navigator.pop(context);
                  },
                  child: const Text('Adicionar'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class ClienteDashboard extends StatelessWidget {
  const ClienteDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context);
    final agendaService = Provider.of<AgendaService>(context);

    final meusAgendamentos = agendaService.agendamentos
        .where((ag) => ag.clienteId == auth.user!.uid)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Meus Agendamentos'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => auth.logout(),
          ),
        ],
      ),
      body: meusAgendamentos.isEmpty
          ? const Center(child: Text('Nenhum agendamento encontrado'))
          : ListView.builder(
        itemCount: meusAgendamentos.length,
        itemBuilder: (context, index) {
          final ag = meusAgendamentos[index];
          return Card(
            margin: const EdgeInsets.all(8),
            child: ListTile(
              title: Text(ag.clienteNome),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var servico in ag.servicos)
                    Text('• ${servico.nome} - ${servico.duracao}min - R\$${servico.valor.toStringAsFixed(2)}'),
                  Text('${DateFormat('dd/MM/yyyy').format(ag.data)} - ${ag.horario}'),
                  Text('Duração total: ${ag.duracaoTotal}min'),
                  Text('Total: R\$${ag.valorTotal.toStringAsFixed(2)}'),
                  Text('Status: ${ag.status}'),
                  if (ag.motivoCancelamento != null)
                    Text('Motivo cancelamento: ${ag.motivoCancelamento}'),
                ],
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (ag.status == 'Pendente' || ag.status == 'Aprovado')
                    IconButton(
                      icon: const Icon(Icons.edit, color: Colors.blue),
                      onPressed: () => _editarAgendamento(context, ag),
                    ),
                  if (ag.status == 'Pendente' || ag.status == 'Aprovado')
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => _cancelarAgendamento(context, ag.id),
                    ),
                ],
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const ClienteHomeScreen()),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  void _editarAgendamento(BuildContext context, Agendamento agendamento) {
    Navigator.push(
        context,
        MaterialPageRoute(
        builder: (context) => EditarAgendamentoScreen(agendamento: agendamento),
    ));
  }

  void _cancelarAgendamento(BuildContext context, String agendamentoId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancelar Agendamento'),
        content: const Text('Tem certeza que deseja cancelar este agendamento?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Não'),
          ),
          ElevatedButton(
            onPressed: () {
              Provider.of<AgendaService>(context, listen: false)
                  .cancelarAgendamento(agendamentoId, 'Cancelado pelo cliente');
              Navigator.pop(context);
            },
            child: const Text('Sim'),
          ),
        ],
      ),
    );
  }
}

class ClienteHomeScreen extends StatelessWidget {
  const ClienteHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final agendaService = Provider.of<AgendaService>(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Serviços Disponíveis')),
      body: agendaService.servicos.isEmpty
          ? const Center(child: Text('Nenhum serviço disponível'))
          : ListView.builder(
        itemCount: agendaService.servicos.length,
        itemBuilder: (context, index) {
          final servico = agendaService.servicos[index];
          return Card(
            margin: const EdgeInsets.all(8),
            child: ListTile(
              title: Text(servico.nome),
              subtitle: Text('${servico.duracao}min - R\$${servico.valor.toStringAsFixed(2)}'),
              trailing: const Icon(Icons.arrow_forward),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => AgendamentoScreen(servico: servico),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class AgendamentoScreen extends StatefulWidget {
  final Servico servico;

  const AgendamentoScreen({super.key, required this.servico});

  @override
  State<AgendamentoScreen> createState() => _AgendamentoScreenState();
}

class _AgendamentoScreenState extends State<AgendamentoScreen> {
  DateTime _selectedDate = DateTime.now();
  String? _selectedTime;
  final List<Servico> _servicosSelecionados = [];

  List<String> _horariosDisponiveis = [];

  @override
  void initState() {
    super.initState();
    _servicosSelecionados.add(widget.servico);
    _loadHorarios();
  }

  void _loadHorarios() async {
    final agendaService = Provider.of<AgendaService>(context, listen: false);
    final slots = agendaService.gerarSlotsDisponiveis(
      _selectedDate,
      _servicosSelecionados.fold(0, (sum, s) => sum + s.duracao),
    );
    setState(() => _horariosDisponiveis = slots);
  }

  @override
  Widget build(BuildContext context) {
    final agendaService = Provider.of<AgendaService>(context);
    final auth = Provider.of<AuthService>(context);

    return Scaffold(
      appBar: AppBar(title: Text('Agendar Serviços')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Serviços Selecionados:',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            ..._servicosSelecionados.map((servico) => ListTile(
              title: Text(servico.nome),
              trailing: IconButton(
                icon: const Icon(Icons.remove_circle, color: Colors.red),
                onPressed: () {
                  setState(() {
                    _servicosSelecionados.remove(servico);
                    _loadHorarios();
                  });
                },
              ),
              subtitle: Text('${servico.duracao}min - R\$${servico.valor.toStringAsFixed(2)}'),
            )),

            const SizedBox(height: 20),
            Text(
              'Adicionar mais serviços:',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            ...agendaService.servicos
                .where((s) => !_servicosSelecionados.contains(s))
                .map((servico) => ListTile(
              title: Text(servico.nome),
              trailing: const Icon(Icons.add_circle, color: Colors.green),
              subtitle: Text('${servico.duracao}min - R\$${servico.valor.toStringAsFixed(2)}'),
              onTap: () {
                setState(() {
                  _servicosSelecionados.add(servico);
                  _loadHorarios();
                });
              },
            )),

            const SizedBox(height: 20),
            Text(
              'Seus dados:',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text('Nome: ${auth.userName}'),
            Text('Email: ${auth.userEmail}'),

            const SizedBox(height: 20),
            Text(
              'Selecione a data:',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            ElevatedButton(
              onPressed: () => _selectDate(context),
              child: Text(DateFormat('dd/MM/yyyy').format(_selectedDate)),
            ),
            const SizedBox(height: 20),
            Text(
              'Selecione o horário:',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            _horariosDisponiveis.isEmpty
                ? const Text('Nenhum horário disponível para esta data')
                : Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _horariosDisponiveis.map((horario) {
                return ChoiceChip(
                  label: Text(horario),
                  selected: _selectedTime == horario,
                  onSelected: (selected) {
                    setState(() {
                      _selectedTime = selected ? horario : null;
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 30),
            Center(
              child: ElevatedButton(
                onPressed: _selectedTime == null || _servicosSelecionados.isEmpty
                    ? null
                    : () {
                  final novoAgendamento = Agendamento(
                    id: '',
                    clienteId: auth.user?.uid ?? '',
                    clienteNome: auth.userName ?? '',
                    clienteEmail: auth.userEmail ?? '',
                    servicos: _servicosSelecionados,
                    data: _selectedDate,
                    horario: _selectedTime!,
                  );

                  agendaService.adicionarAgendamento(novoAgendamento);

                  // Bloquear horário temporariamente
                  final partes = _selectedTime!.split(':');
                  final hora = int.parse(partes[0]);
                  final minuto = int.parse(partes[1]);
                  agendaService.bloquearHorario(DateTime(
                    _selectedDate.year,
                    _selectedDate.month,
                    _selectedDate.day,
                    hora,
                    minuto,
                  ));

                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Agendamento solicitado!'),
                      content: Text(
                          'Seu agendamento foi solicitado. Aguarde a confirmação do pedreiro.'),
                      actions: [
                        TextButton(
                          onPressed: () {
                            Navigator.popUntil(context, (route) => route.isFirst);
                          },
                          child: const Text('OK'),
                        ),
                      ],
                    ),
                  );
                },
                child: const Text('Solicitar Agendamento'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 60)),
    );

    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
        _selectedTime = null;
        _loadHorarios();
      });
    }
  }
}

class EditarAgendamentoScreen extends StatefulWidget {
  final Agendamento agendamento;

  const EditarAgendamentoScreen({super.key, required this.agendamento});

  @override
  State<EditarAgendamentoScreen> createState() => _EditarAgendamentoScreenState();
}

class _EditarAgendamentoScreenState extends State<EditarAgendamentoScreen> {
  late DateTime _selectedDate;
  String? _selectedTime;
  List<String> _horariosDisponiveis = [];
  late List<Servico> _servicosSelecionados;
  final List<Servico> _todosServicos = [];

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.agendamento.data;
    _selectedTime = widget.agendamento.horario;
    _servicosSelecionados = widget.agendamento.servicos;
    _todosServicos.addAll(Provider.of<AgendaService>(context, listen: false).servicos);
    _loadHorarios();
  }

  void _loadHorarios() {
    final agendaService = Provider.of<AgendaService>(context, listen: false);
    final slots = agendaService.gerarSlotsDisponiveis(
      _selectedDate,
      _servicosSelecionados.fold(0, (sum, s) => sum + s.duracao),
    );
    setState(() => _horariosDisponiveis = slots);
  }

  @override
  Widget build(BuildContext context) {
    final agendaService = Provider.of<AgendaService>(context);
    final auth = Provider.of<AuthService>(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Editar Agendamento')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Serviços Selecionados:',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            ..._servicosSelecionados.map((servico) => ListTile(
              title: Text(servico.nome),
              trailing: IconButton(
                icon: const Icon(Icons.remove_circle, color: Colors.red),
                onPressed: () {
                  setState(() {
                    _servicosSelecionados.remove(servico);
                    _loadHorarios();
                  });
                },
              ),
              subtitle: Text('${servico.duracao}min - R\$${servico.valor.toStringAsFixed(2)}'),
            )),

            const SizedBox(height: 20),
            Text(
              'Adicionar mais serviços:',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            ..._todosServicos
                .where((s) => !_servicosSelecionados.contains(s))
                .map((servico) => ListTile(
              title: Text(servico.nome),
              trailing: const Icon(Icons.add_circle, color: Colors.green),
              subtitle: Text('${servico.duracao}min - R\$${servico.valor.toStringAsFixed(2)}'),
              onTap: () {
                setState(() {
                  _servicosSelecionados.add(servico);
                  _loadHorarios();
                });
              },
            )),

            const SizedBox(height: 20),
            Text(
              'Selecione a nova data:',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            ElevatedButton(
              onPressed: () => _selectDate(context),
              child: Text(DateFormat('dd/MM/yyyy').format(_selectedDate)),
            ),
            const SizedBox(height: 20),
            Text(
              'Selecione o novo horário:',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            _horariosDisponiveis.isEmpty
                ? const Text('Nenhum horário disponível para esta data')
                : Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _horariosDisponiveis.map((horario) {
                return ChoiceChip(
                  label: Text(horario),
                  selected: _selectedTime == horario,
                  onSelected: (selected) {
                    setState(() {
                      _selectedTime = selected ? horario : null;
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 30),
            Center(
              child: ElevatedButton(
                onPressed: _selectedTime == null || _servicosSelecionados.isEmpty
                    ? null
                    : () {
                  final agendamentoAtualizado = Agendamento(
                    id: widget.agendamento.id,
                    clienteId: auth.user?.uid ?? '',
                    clienteNome: auth.userName ?? '',
                    clienteEmail: auth.userEmail ?? '',
                    servicos: _servicosSelecionados,
                    data: _selectedDate,
                    horario: _selectedTime!,
                    status: 'Pendente', // Volta para pendente ao editar
                  );

                  // Desbloquear horário antigo
                  final partesAntigo = widget.agendamento.horario.split(':');
                  final horaAntigo = int.parse(partesAntigo[0]);
                  final minutoAntigo = int.parse(partesAntigo[1]);
                  agendaService.desbloquearHorario(DateTime(
                    widget.agendamento.data.year,
                    widget.agendamento.data.month,
                    widget.agendamento.data.day,
                    horaAntigo,
                    minutoAntigo,
                  ));

                  // Bloquear novo horário
                  final partesNovo = _selectedTime!.split(':');
                  final horaNovo = int.parse(partesNovo[0]);
                  final minutoNovo = int.parse(partesNovo[1]);
                  agendaService.bloquearHorario(DateTime(
                    _selectedDate.year,
                    _selectedDate.month,
                    _selectedDate.day,
                    horaNovo,
                    minutoNovo,
                  ));

                  agendaService.atualizarAgendamento(agendamentoAtualizado);

                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Agendamento atualizado com sucesso!')),
                  );
                },
                child: const Text('Atualizar Agendamento'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 60)),
    );

    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
        _selectedTime = null;
        _loadHorarios();
      });
    }
  }
}

// Helper function
bool isSameDay(DateTime? a, DateTime? b) {
  if (a == null || b == null) return false;
  return a.year == b.year && a.month == b.month && a.day == b.day;
}