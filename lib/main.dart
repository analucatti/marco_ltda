import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
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

  User? get user => _user;

  AuthService() {
    _setupAuthListener();
  }

  void _setupAuthListener() {
    FirebaseAuth.instance.authStateChanges().listen((User? user) {
      _user = user;
      notifyListeners();
    });
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
    } on FirebaseAuthException catch (e) {
      throw Exception(e.message);
    }
  }

  Future<void> logout() async {
    await FirebaseAuth.instance.signOut();
  }
}

class AgendaService with ChangeNotifier {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  List<Servico> _servicos = [];
  List<Agendamento> _agendamentos = [];
  List<DateTime> _horariosBloqueados = [];

  List<Servico> get servicos => _servicos;
  List<Agendamento> get agendamentos => _agendamentos;
  List<DateTime> get horariosBloqueados => _horariosBloqueados;

  AgendaService() {
    _carregarDados();
  }

  Future<void> _carregarDados() async {
    await _carregarServicos();
    await _carregarAgendamentos();
    await _carregarHorariosBloqueados();
  }

  // CORREÇÃO: Leitura correta dos serviços com ID do documento
  Future<void> _carregarServicos() async {
    final snapshot = await _db.collection('servicos').get();
    _servicos = snapshot.docs.map((doc) {
      final data = doc.data();
      return Servico(
        id: doc.id, // Usa o ID do documento
        nome: data['nome'] ?? '',
        valor: (data['valor'] as num).toDouble(),
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

  Future<void> _carregarHorariosBloqueados() async {
    final snapshot = await _db.collection('horarios_bloqueados').get();
    _horariosBloqueados = snapshot.docs
        .map((doc) => (doc['data'] as Timestamp).toDate())
        .toList();
    notifyListeners();
  }

  // CORREÇÃO: Não gera ID manualmente
  Future<void> adicionarServico(String nome, double valor) async {
    await _db.collection('servicos').add({
      'nome': nome,
      'valor': valor,
    });
    await _carregarServicos();
  }

  Future<void> adicionarAgendamento(Agendamento agendamento) async {
    await _db.collection('agendamentos').add({
      'clienteId': agendamento.clienteId,
      'clienteNome': agendamento.clienteNome,
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

  Future<void> cancelarAgendamento(String id) async {
    await _db.collection('agendamentos').doc(id).delete();
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
}

class Servico {
  final String id;
  final String nome;
  final double valor;

  Servico({
    required this.id,
    required this.nome,
    required this.valor,
  });

  factory Servico.fromMap(Map<String, dynamic> map) {
    return Servico(
      id: map['id'] ?? '',
      nome: map['nome'] ?? '',
      valor: (map['valor'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nome': nome,
      'valor': valor,
    };
  }
}

class Agendamento {
  final String id;
  final String clienteId;
  final String clienteNome;
  List<Servico> servicos;
  DateTime data;
  String horario;
  String status;

  Agendamento({
    required this.id,
    required this.clienteId,
    required this.clienteNome,
    required this.servicos,
    required this.data,
    required this.horario,
    this.status = 'Pendente',
  });

  factory Agendamento.fromMap(Map<String, dynamic> map, String docId) {
    return Agendamento(
      id: docId,
      clienteId: map['clienteId'] ?? '',
      clienteNome: map['clienteNome'] ?? '',
      servicos: (map['servicos'] as List<dynamic>)
          .map((s) => Servico.fromMap(s))
          .toList(),
      data: (map['data'] as Timestamp).toDate(),
      horario: map['horario'] ?? '',
      status: map['status'] ?? 'Pendente',
    );
  }

  double get valorTotal {
    return servicos.fold(0, (sum, servico) => sum + servico.valor);
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

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    Provider.of<AgendaService>(context, listen: false)._carregarDados();
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
      body: Column(
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
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAdicionarServicoDialog(context),
        child: const Icon(Icons.add),
      ),
    );
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
                  Text('• ${servico.nome} - R\$${servico.valor.toStringAsFixed(2)}'),
                Text('${DateFormat('dd/MM/yyyy').format(ag.data)} - ${ag.horario}'),
                Text('Total: R\$${ag.valorTotal.toStringAsFixed(2)}'),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (ag.status == 'Pendente')
                  IconButton(
                    icon: const Icon(Icons.check, color: Colors.green),
                    onPressed: () => agendaService.atualizarStatusAgendamento(ag.id, 'Aprovado'),
                  ),
                if (ag.status == 'Pendente')
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.red),
                    onPressed: () => agendaService.atualizarStatusAgendamento(ag.id, 'Rejeitado'),
                  ),
                Chip(
                  label: Text(ag.status),
                  backgroundColor: ag.status == 'Aprovado'
                      ? Colors.green[100]
                      : ag.status == 'Rejeitado'
                      ? Colors.red[100]
                      : Colors.blue[100],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showAdicionarServicoDialog(BuildContext context) {
    final nomeController = TextEditingController();
    final valorController = TextEditingController();

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
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                if (nomeController.text.isNotEmpty && valorController.text.isNotEmpty) {
                  Provider.of<AgendaService>(context, listen: false).adicionarServico(
                    nomeController.text,
                    double.parse(valorController.text),
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
              subtitle: Text('R\$${servico.valor.toStringAsFixed(2)}'),
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
                    Text('• ${servico.nome} - R\$${servico.valor.toStringAsFixed(2)}'),
                  Text('${DateFormat('dd/MM/yyyy').format(ag.data)} - ${ag.horario}'),
                  Text('Total: R\$${ag.valorTotal.toStringAsFixed(2)}'),
                  Text('Status: ${ag.status}'),
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
                  .cancelarAgendamento(agendamentoId);
              Navigator.pop(context);
            },
            child: const Text('Sim'),
          ),
        ],
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
  final _nomeController = TextEditingController();
  final _emailController = TextEditingController();
  final List<Servico> _servicosSelecionados = [];

  final List<String> _horariosDisponiveis = [
    '08:00', '09:00', '10:00', '11:00',
    '13:00', '14:00', '15:00', '16:00'
  ];

  @override
  void initState() {
    super.initState();
    _servicosSelecionados.add(widget.servico);
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
                  });
                },
              ),
              subtitle: Text('R\$${servico.valor.toStringAsFixed(2)}'),
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
              subtitle: Text('R\$${servico.valor.toStringAsFixed(2)}'),
              onTap: () {
                setState(() {
                  _servicosSelecionados.add(servico);
                });
              },
            )),

            const SizedBox(height: 20),
            Text(
              'Seus dados:',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            TextField(
              controller: _nomeController,
              decoration: const InputDecoration(labelText: 'Nome completo'),
            ),
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
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _horariosDisponiveis.map((horario) {
                final horarioDateTime = DateTime(
                  _selectedDate.year,
                  _selectedDate.month,
                  _selectedDate.day,
                  int.parse(horario.split(':')[0]),
                );

                final isBloqueado = agendaService.horariosBloqueados
                    .any((hb) => isSameHour(hb, horarioDateTime));

                return ChoiceChip(
                  label: Text(horario),
                  selected: _selectedTime == horario && !isBloqueado,
                  disabledColor: Colors.grey,
                  onSelected: isBloqueado
                      ? null
                      : (selected) {
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
                onPressed: _selectedTime == null ||
                    _nomeController.text.isEmpty ||
                    _servicosSelecionados.isEmpty
                    ? null
                    : () {
                  final novoAgendamento = Agendamento(
                    id: '',
                    clienteId: auth.user?.uid ?? '',
                    clienteNome: _nomeController.text,
                    servicos: _servicosSelecionados,
                    data: _selectedDate,
                    horario: _selectedTime!,
                  );

                  agendaService.adicionarAgendamento(novoAgendamento);

                  // Bloquear horário temporariamente
                  agendaService.bloquearHorario(DateTime(
                    _selectedDate.year,
                    _selectedDate.month,
                    _selectedDate.day,
                    int.parse(_selectedTime!.split(':')[0]),
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
      });
    }
  }

  bool isSameHour(DateTime dt1, DateTime dt2) {
    return dt1.year == dt2.year &&
        dt1.month == dt2.month &&
        dt1.day == dt2.day &&
        dt1.hour == dt2.hour;
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
  final List<String> _horariosDisponiveis = [
    '08:00', '09:00', '10:00', '11:00',
    '13:00', '14:00', '15:00', '16:00'
  ];
  late List<Servico> _servicosSelecionados;
  final List<Servico> _todosServicos = [];

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.agendamento.data;
    _selectedTime = widget.agendamento.horario;
    _servicosSelecionados = widget.agendamento.servicos;
    _todosServicos.addAll(Provider.of<AgendaService>(context, listen: false).servicos);
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
                  });
                },
              ),
              subtitle: Text('R\$${servico.valor.toStringAsFixed(2)}'),
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
              subtitle: Text('R\$${servico.valor.toStringAsFixed(2)}'),
              onTap: () {
                setState(() {
                  _servicosSelecionados.add(servico);
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
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _horariosDisponiveis.map((horario) {
                final horarioDateTime = DateTime(
                  _selectedDate.year,
                  _selectedDate.month,
                  _selectedDate.day,
                  int.parse(horario.split(':')[0]),
                );

                final isBloqueado = agendaService.horariosBloqueados
                    .any((hb) => isSameHour(hb, horarioDateTime));

                return ChoiceChip(
                  label: Text(horario),
                  selected: _selectedTime == horario && !isBloqueado,
                  disabledColor: Colors.grey,
                  onSelected: isBloqueado
                      ? null
                      : (selected) {
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
                    clienteNome: widget.agendamento.clienteNome,
                    servicos: _servicosSelecionados,
                    data: _selectedDate,
                    horario: _selectedTime!,
                    status: 'Pendente', // Volta para pendente ao editar
                  );

                  // Desbloquear horário antigo
                  agendaService.desbloquearHorario(DateTime(
                    widget.agendamento.data.year,
                    widget.agendamento.data.month,
                    widget.agendamento.data.day,
                    int.parse(widget.agendamento.horario.split(':')[0]),
                  ));

                  // Bloquear novo horário
                  agendaService.bloquearHorario(DateTime(
                    _selectedDate.year,
                    _selectedDate.month,
                    _selectedDate.day,
                    int.parse(_selectedTime!.split(':')[0]),
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
      });
    }
  }

  bool isSameHour(DateTime dt1, DateTime dt2) {
    return dt1.year == dt2.year &&
        dt1.month == dt2.month &&
        dt1.day == dt2.day &&
        dt1.hour == dt2.hour;
  }
}