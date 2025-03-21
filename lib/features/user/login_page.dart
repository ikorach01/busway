import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:bus_app/features/user/ask_location.dart';
import 'package:bus_app/features/shared/role_selection.dart';
import 'package:bus_app/features/driver/auth/add_information.dart';
import 'dart:ui';

final supabase = Supabase.instance.client;

class LoginPage extends StatefulWidget {
  final String? userType; // Nullable to allow selection for new users
  const LoginPage({super.key, this.userType});

  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController = TextEditingController();

  bool isLogin = true;
  bool isLoading = false;

  Future<void> _authenticate() async {
    setState(() => isLoading = true);

    try {
      if (isLogin) {
        print('Attempting to sign in with email: ${emailController.text.trim()}');
        
        final response = await supabase.auth.signInWithPassword(
          email: emailController.text.trim(),
          password: passwordController.text.trim(),
        );

        final user = response.user;
        if (user == null) {
          throw Exception('Login failed. Please check your credentials.');
        }
        
        print('User signed in successfully: ${user.id}');
        
        if (user.emailConfirmedAt == null) {
          throw Exception('Please confirm your email before logging in.');
        }

        // جلب بيانات المستخدم من Supabase
        final session = supabase.auth.currentSession;
        final userData = session?.user.userMetadata;
        final role = userData?['role'] as String?;
        
        print('User metadata: $userData');
        print('User role: $role');
        
        // Check if user exists in the database and insert if not
        await _checkAndInsertUserData(user, role);

        if (role == null) {
          // المستخدم يسجل الدخول لأول مرة ولم يحدد دوره بعد
          print('First-time login detected. Redirecting to role selection.');
          if (!context.mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => RoleSelectionPage(
                userId: user.id,
                userEmail: user.email ?? '',
                userPhone: userData?['phone'] as String? ?? '',
              ),
            ),
          );
        } else {
          // المستخدم لديه دور مسجل، الانتقال بناءً على الدور
          print('Existing user detected with role: $role. Redirecting accordingly.');
          if (!context.mounted) return;
          if (role == 'passenger') {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const AskLocationScreen()),
            );
          } else if (role == 'driver') {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const AddInformationPage()),
            );
          }
        }
      } else {
        if (passwordController.text != confirmPasswordController.text) {
          throw Exception("Passwords do not match.");
        }

        print('Attempting to sign up with email: ${emailController.text.trim()}');
        
        final response = await supabase.auth.signUp(
          email: emailController.text.trim(),
          password: passwordController.text.trim(),
          emailRedirectTo: 'bus_app://auth/callback',
          data: {
            'phone': phoneController.text.trim(),
            'role': null, // لم يتم تحديد الدور بعد، سيتم تحديده لاحقًا
          },
        );

        final user = response.user;
        if (user != null) {
          print('User signed up successfully: ${user.id}');
          
          // Insert user data into the users table
          try {
            print('Attempting to insert user data into users table...');
            print('User ID: ${user.id}');
            print('Email: ${emailController.text.trim()}');
            print('Phone: ${phoneController.text.trim()}');
            
            // Check if the users table exists and is accessible
            try {
              final tableCheck = await supabase.from('users').select('count').limit(1);
              print('Users table check result: $tableCheck');
            } catch (tableError) {
              print('Error checking users table: $tableError');
              print('This may indicate that the users table does not exist or you do not have access to it');
            }
            
            // Get schema information
            try {
              // Use REST API directly to avoid execute method issue
              final schemaInfo = await supabase
                  .from('information_schema.tables')
                  .select('table_name, table_schema')
                  .eq('table_name', 'users');
              print('Schema info for users table: $schemaInfo');
            } catch (schemaError) {
              print('Error getting schema info: $schemaError');
            }
            
            // Try multiple approaches to insert the user data
            await _insertUserWithMultipleApproaches(user);
          } catch (dbError) {
            print('Error in database operations: $dbError');
          }
          
          _showMessage('Registration successful! Please check your email to confirm your account.', Colors.green);
          
          setState(() {
            isLogin = true; // التبديل إلى وضع تسجيل الدخول
          });
        }
      }
    } catch (e) {
      print('Authentication error: $e');
      _showMessage(e.toString(), Colors.red);
    }

    setState(() => isLoading = false);
  }
  
  // Helper function to check if user exists in database and insert if not
  Future<void> _checkAndInsertUserData(User user, String? role) async {
    try {
      print('Checking if user exists in database: ${user.id}');
      
      // Check if user exists in the users table
      final existingUser = await supabase
          .from('users')
          .select()
          .eq('id', user.id)
          .maybeSingle();
      
      print('Existing user check result: $existingUser');
      
      if (existingUser == null) {
        print('User not found in database, inserting now...');
        await _insertUserWithMultipleApproaches(user, role: role);
      } else {
        print('User already exists in database');
        
        // Update role if needed
        if (role != null && (existingUser['role'] == null || existingUser['role'] != role)) {
          print('Updating user role to: $role');
          await supabase
              .from('users')
              .update({
                'role': role,
                'updated_at': DateTime.now().toIso8601String()
              })
              .eq('id', user.id);
          print('User role updated successfully');
        }
      }
    } catch (e) {
      print('Error in _checkAndInsertUserData: $e');
    }
  }
  
  // Helper function to try multiple approaches for inserting user data
  Future<void> _insertUserWithMultipleApproaches(User user, {String? role}) async {
    // Try direct SQL query using stored procedure
    try {
      print('Approach 1: Using stored procedure...');
      await supabase.rpc('create_user', params: {
        'user_id': user.id,
        'user_email': user.email ?? emailController.text.trim(),
        'user_phone': phoneController.text.trim(),
        'user_role': role,
      });
      print('User created via stored procedure');
      return; // Exit if successful
    } catch (rpcError) {
      print('Error with stored procedure: $rpcError');
    }
    
    // Approach 2: Standard insert
    try {
      print('Approach 2: Standard insert...');
      final userData = {
        'id': user.id,
        'email': user.email ?? emailController.text.trim(),
        'phone': phoneController.text.trim(),
        'created_at': DateTime.now().toIso8601String(),
      };
      
      // Add role if provided
      if (role != null) {
        userData['role'] = role;
      }
      
      print('Inserting data: $userData');
      await supabase.from('users').insert(userData);
      print('User data inserted into users table');
      return; // Exit if successful
    } catch (insertError) {
      print('Error with standard insert: $insertError');
      
      if (insertError is PostgrestException) {
        print('PostgrestException code: ${insertError.code}');
        print('PostgrestException message: ${insertError.message}');
        print('PostgrestException details: ${insertError.details}');
      }
    }
    
    // Approach 3: Upsert
    try {
      print('Approach 3: Trying upsert...');
      final userData = {
        'id': user.id,
        'email': user.email ?? emailController.text.trim(),
        'phone': phoneController.text.trim(),
      };
      
      // Add role if provided
      if (role != null) {
        userData['role'] = role;
      }
      
      await supabase.from('users').upsert(userData);
      print('User upserted successfully');
      return; // Exit if successful
    } catch (upsertError) {
      print('Error with upsert: $upsertError');
    }
    
    // Approach 4: Minimal insert
    try {
      print('Approach 4: Minimal insert...');
      final userData = {
        'id': user.id,
        'email': user.email ?? emailController.text.trim(),
      };
      
      // Add role if provided
      if (role != null) {
        userData['role'] = role;
      }
      
      await supabase.from('users').insert(userData);
      print('Minimal user record created');
    } catch (minimalError) {
      print('Error with minimal insert: $minimalError');
    }
  }

  void _showMessage(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color, duration: const Duration(seconds: 3)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF14212F),
      body: Center(
        child: Container(
          width: 350,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isLogin ? 'Sign In' : 'Sign Up',
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 16),
              _buildTextField(emailController, 'Email', Icons.email),
              if (!isLogin) _buildTextField(phoneController, 'Phone Number', Icons.phone),
              _buildTextField(passwordController, 'Password', Icons.lock, isPassword: true),
              if (!isLogin) _buildTextField(confirmPasswordController, 'Confirm Password', Icons.lock, isPassword: true),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: isLoading ? null : _authenticate,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: const Color(0xFF2A52CA),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(isLogin ? 'Login' : 'Register', style: const TextStyle(fontSize: 18, color: Colors.white)),
              ),
              TextButton(
                onPressed: () => setState(() => isLogin = !isLogin),
                child: Text(
                  isLogin ? 'Create an account' : 'Already have an account? Sign in',
                  style: const TextStyle(color: Color(0xFF9CB3FA)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, IconData icon, {bool isPassword = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        obscureText: isPassword,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
          prefixIcon: Icon(icon, color: Colors.white.withOpacity(0.7)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFF2A52CA)),
          ),
          filled: true,
          fillColor: Colors.white.withOpacity(0.1),
        ),
      ),
    );
  }
}