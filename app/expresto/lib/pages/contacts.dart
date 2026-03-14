import 'package:expresto/core/api_client.dart';
import 'package:expresto/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:graphql_flutter/graphql_flutter.dart';

class EmergencyContactsPage extends StatefulWidget {
  const EmergencyContactsPage({super.key});

  @override
  State<EmergencyContactsPage> createState() => _EmergencyContactsPageState();
}

class _BackendContact {
  const _BackendContact({
    required this.id,
    required this.name,
    required this.phone,
    required this.relationship,
    required this.isPrimary,
  });

  final String id;
  final String name;
  final String phone;
  final String relationship;
  final bool isPrimary;
}

const String _kQueryContacts = r'''
  query EmergencyContacts {
    emergencyContacts {
      id
      name
      phone
      relationship
      isPrimary
    }
  }
''';

const String _kMutationAdd = r'''
  mutation AddEmergencyContact($name: String!, $phone: String!, $relationship: String!) {
    addEmergencyContact(input: { name: $name, phone: $phone, relationship: $relationship }) {
      id
      name
      phone
      relationship
      isPrimary
    }
  }
''';

const String _kMutationDelete = r'''
  mutation DeleteEmergencyContact($id: ID!) {
    deleteEmergencyContact(id: $id)
  }
''';

class _EmergencyContactsPageState extends State<EmergencyContactsPage> {
  List<_BackendContact> _contacts = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchContacts();
  }

  Future<void> _fetchContacts() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await ApiClient.client.value.query(
        QueryOptions(
          document: gql(_kQueryContacts),
          fetchPolicy: FetchPolicy.networkOnly,
        ),
      );
      if (!mounted) return;
      if (result.hasException) {
        setState(() {
          _error = result.exception.toString();
          _loading = false;
        });
        return;
      }
      final list = (result.data?['emergencyContacts'] as List?) ?? [];
      setState(() {
        _contacts = list
            .map(
              (c) => _BackendContact(
                id: c['id'] as String,
                name: c['name'] as String,
                phone: c['phone'] as String,
                relationship: c['relationship'] as String? ?? '',
                isPrimary: c['isPrimary'] as bool? ?? false,
              ),
            )
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _deleteContact(String id) async {
    try {
      await ApiClient.client.value.mutate(
        MutationOptions(document: gql(_kMutationDelete), variables: {'id': id}),
      );
      _fetchContacts();
    } catch (_) {}
  }

  void _showAddSheet() {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final relCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.panel,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
            left: 16,
            right: 16,
            top: 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Add Emergency Contact',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 20),
              _field(nameCtrl, 'Name'),
              const SizedBox(height: 12),
              _field(phoneCtrl, 'Phone Number', type: TextInputType.phone),
              const SizedBox(height: 12),
              _field(relCtrl, 'Relationship (e.g. Parent)'),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.blue,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () async {
                    if (nameCtrl.text.isEmpty || phoneCtrl.text.isEmpty) return;
                    Navigator.pop(ctx);
                    await ApiClient.client.value.mutate(
                      MutationOptions(
                        document: gql(_kMutationAdd),
                        variables: {
                          'name': nameCtrl.text.trim(),
                          'phone': phoneCtrl.text.trim(),
                          'relationship': relCtrl.text.trim().isEmpty
                              ? 'Contact'
                              : relCtrl.text.trim(),
                        },
                      ),
                    );
                    _fetchContacts();
                  },
                  child: const Text(
                    'Save Contact',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  TextField _field(
    TextEditingController ctrl,
    String label, {
    TextInputType type = TextInputType.text,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: type,
      style: const TextStyle(color: AppColors.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppColors.textMuted),
        enabledBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.shellBorder),
        ),
        focusedBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.blue),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(context),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppColors.panel,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.shellBorder),
                ),
                child: const Icon(
                  Icons.contacts_outlined,
                  color: AppColors.textPrimary,
                  size: 16,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Emergency Contacts',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
          Row(
            children: [
              GestureDetector(
                onTap: _fetchContacts,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.panel,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.shellBorder),
                  ),
                  child: const Icon(
                    Icons.refresh_rounded,
                    color: AppColors.textMuted,
                    size: 18,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.panel,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.shellBorder),
                  ),
                  child: const Icon(
                    Icons.home_filled,
                    color: AppColors.textMuted,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.blue),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                color: AppColors.emergency,
                size: 40,
              ),
              const SizedBox(height: 12),
              Text(
                'Could not load contacts',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.blue,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: _fetchContacts,
                child: const Text(
                  'Retry',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        const SizedBox(height: 4),
        if (_contacts.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.panel,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.shellBorder),
            ),
            child: const Column(
              children: [
                Icon(
                  Icons.person_add_alt_1_outlined,
                  color: AppColors.textMuted,
                  size: 36,
                ),
                SizedBox(height: 12),
                Text(
                  'No emergency contacts yet',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Add contacts who will be notified\nin case of an emergency.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: AppColors.panel,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.shellBorder),
            ),
            child: Column(
              children: [
                for (int i = 0; i < _contacts.length; i++) ...[
                  if (i > 0) Divider(color: AppColors.shellBorder, height: 1),
                  _ContactTile(
                    contact: _contacts[i],
                    onDelete: () => _deleteContact(_contacts[i].id),
                  ),
                ],
              ],
            ),
          ),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: _showAddSheet,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.blue.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.blue.withValues(alpha: 0.4)),
            ),
            alignment: Alignment.center,
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add, color: AppColors.blue, size: 18),
                SizedBox(width: 6),
                Text(
                  'Add Contact',
                  style: TextStyle(
                    color: AppColors.blue,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }
}

class _ContactTile extends StatelessWidget {
  const _ContactTile({required this.contact, required this.onDelete});

  final _BackendContact contact;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: contact.isPrimary
                  ? AppColors.emergency.withValues(alpha: 0.15)
                  : AppColors.blue.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              contact.isPrimary
                  ? Icons.star_rounded
                  : Icons.person_outline_rounded,
              color: contact.isPrimary ? AppColors.emergency : AppColors.blue,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      contact.name,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (contact.isPrimary) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.emergency.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'PRIMARY',
                          style: TextStyle(
                            color: AppColors.emergency,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  contact.phone,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 13,
                  ),
                ),
                if (contact.relationship.isNotEmpty)
                  Text(
                    contact.relationship,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            onPressed: onDelete,
            icon: const Icon(
              Icons.delete_outline_rounded,
              color: AppColors.textMuted,
              size: 20,
            ),
            style: IconButton.styleFrom(
              backgroundColor: AppColors.panelSoft,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
