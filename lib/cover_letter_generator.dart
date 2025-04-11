import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class CoverLetterGenerator extends StatefulWidget {
  final String apiKey;

  const CoverLetterGenerator({
    Key? key,
    required this.apiKey,
  }) : super(key: key);

  @override
  _CoverLetterGeneratorState createState() => _CoverLetterGeneratorState();
}

class _CoverLetterGeneratorState extends State<CoverLetterGenerator> {
  final TextEditingController _jobDescriptionController =
      TextEditingController();
  String _resumeFilePath = '';
  String _resumeFileName = '';
  File? _resumeFile;
  String _coverLetter = '';
  bool _isLoading = false;
  bool _isStreaming = false;
  String _errorMessage = '';
  bool _isSaving = false;
  String _savedFilePath = '';

  // Google Gemini API streaming endpoint
  final String _geminiEndpoint =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:streamGenerateContent';

  Future<void> _pickResumeFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (result != null && result.files.single.path != null) {
        setState(() {
          _resumeFilePath = result.files.single.path!;
          _resumeFileName = result.files.single.name;
          _resumeFile = File(_resumeFilePath);
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error picking file: $e';
      });
    }
  }

  Future<void> _generateCoverLetter() async {
    if (_resumeFile == null) {
      setState(() {
        _errorMessage = 'Please select a resume PDF first';
      });
      return;
    }

    if (_jobDescriptionController.text.trim().isEmpty) {
      setState(() {
        _errorMessage = 'Please enter a job description';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _isStreaming = true;
      _errorMessage = '';
      _coverLetter = ''; // Clear previous content
    });

    try {
      // Convert PDF to base64
      final List<int> fileBytes = await _resumeFile!.readAsBytes();
      final String base64File = base64Encode(fileBytes);

      // Prepare request payload for Gemini API
      final Map<String, dynamic> requestBody = {
        "contents": [
          {
            "parts": [
              {
                "text":
                    "Based on the following job description and resume, create a professional, personalized cover letter that highlights the relevant skills and experiences from the resume that match the job requirements. The cover letter should be no longer than one page.\n\nJOB DESCRIPTION:\n${_jobDescriptionController.text}\n\nRESUME (PDF in base64):\n"
              },
              {
                "inlineData": {
                  "mimeType": "application/pdf",
                  "data": base64File
                }
              }
            ]
          }
        ],
        "generationConfig": {
          "temperature": 0.7,
          "topK": 40,
          "topP": 0.95,
          "maxOutputTokens": 1024,
        }
      };

      // Create client for streaming
      final client = http.Client();
      try {
        // Send streaming request
        final request = http.Request(
            'POST', Uri.parse('$_geminiEndpoint?key=${widget.apiKey}&alt=sse'));
        request.headers['Content-Type'] = 'application/json';
        request.body = jsonEncode(requestBody);

        final streamedResponse = await client.send(request);

        if (streamedResponse.statusCode != 200) {
          final errorResponse = await streamedResponse.stream.bytesToString();
          throw Exception(
              'API error: ${streamedResponse.statusCode}, $errorResponse');
        }

        // Process the streaming response
        streamedResponse.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(
          (String line) {
            if (line.startsWith('data: ') && line != 'data: [DONE]') {
              try {
                final jsonData =
                    jsonDecode(line.substring(6)); // Remove 'data: ' prefix

                // Extract text from the response
                if (jsonData['candidates'] != null &&
                    jsonData['candidates'][0]['content'] != null &&
                    jsonData['candidates'][0]['content']['parts'] != null &&
                    jsonData['candidates'][0]['content']['parts'][0]['text'] !=
                        null) {
                  final String textChunk =
                      jsonData['candidates'][0]['content']['parts'][0]['text'];

                  setState(() {
                    _coverLetter += textChunk;
                  });
                }
              } catch (e) {
                print('Error parsing streaming data: $e, line: $line');
              }
            }
          },
          onDone: () {
            setState(() {
              _isLoading = false;
              _isStreaming = false;
            });
            client.close();
          },
          onError: (e) {
            setState(() {
              _errorMessage = 'Streaming error: $e';
              _isLoading = false;
              _isStreaming = false;
            });
            client.close();
          },
          cancelOnError: true,
        );
      } catch (e) {
        client.close();
        throw e;
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error: $e';
        _isLoading = false;
        _isStreaming = false;
      });
    }
  }

  // Function to generate and save PDF
  Future<void> _saveCoverLetterAsPdf() async {
    if (_coverLetter.isEmpty) {
      setState(() {
        _errorMessage = 'No cover letter to save';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = '';
      _savedFilePath = '';
    });

    try {
      // Check storage permission
      var status = await Permission.storage.status;
      if (!status.isGranted) {
        // Request permission
        status = await Permission.storage.request();
        if (!status.isGranted) {
          setState(() {
            _errorMessage = 'Storage permission is required to save the PDF';
            _isSaving = false;
          });
          return;
        }
      }

      // Create PDF document
      final pdf = pw.Document();

      // Add page with formatted cover letter
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Cover Letter',
                  style: pw.TextStyle(
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 20),
                pw.Text(
                  DateTime.now().toString().split(' ')[0], // Current date
                  style: const pw.TextStyle(fontSize: 12),
                ),
                pw.SizedBox(height: 30),
                pw.Text(
                  _coverLetter,
                  style: const pw.TextStyle(
                    fontSize: 12,
                    lineSpacing: 1.5,
                  ),
                ),
              ],
            );
          },
        ),
      );

      // Get downloads directory path based on platform
      Directory? directory;
      if (Platform.isAndroid) {
        // For Android
        directory = Directory('/storage/emulated/0/Download');
        // Ensure directory exists
        if (!await directory.exists()) {
          directory = await getExternalStorageDirectory();
        }
      } else if (Platform.isIOS) {
        // For iOS
        directory = await getApplicationDocumentsDirectory();
      } else {
        // For other platforms
        directory = await getDownloadsDirectory();
      }

      if (directory == null) {
        throw Exception('Could not access downloads directory');
      }

      // Create filename with timestamp to avoid duplicates
      final String fileName =
          'Cover_Letter_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final String filePath = '${directory.path}/$fileName';

      // Save the PDF file
      final File file = File(filePath);
      await file.writeAsBytes(await pdf.save());

      setState(() {
        _isSaving = false;
        _savedFilePath = filePath;
      });

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('PDF saved to: $filePath'),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'OK',
            onPressed: () {},
          ),
        ),
      );
    } catch (e) {
      setState(() {
        _errorMessage = 'Error saving PDF: $e';
        _isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Cover Letter Generator'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Job Description:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _jobDescriptionController,
              maxLines: 5,
              decoration: const InputDecoration(
                hintText: 'Paste the job description here...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Your Resume (PDF):',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _resumeFilePath.isEmpty
                        ? 'No file selected'
                        : 'Selected: $_resumeFileName',
                  ),
                ),
                ElevatedButton(
                  onPressed: _pickResumeFile,
                  child: const Text('Select PDF'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed:
                  (_isLoading || _isStreaming) ? null : _generateCoverLetter,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16),
              ),
              child: _isLoading
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 12),
                        Text(_isStreaming ? 'Generating...' : 'Loading...'),
                      ],
                    )
                  : const Text('Generate Cover Letter'),
            ),
            if (_errorMessage.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                _errorMessage,
                style: const TextStyle(color: Colors.red),
              ),
            ],
            if (_savedFilePath.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'PDF saved to: $_savedFilePath',
                style: const TextStyle(color: Colors.green),
              ),
            ],
            if (_coverLetter.isNotEmpty || _isStreaming) ...[
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Generated Cover Letter:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  if (_isStreaming)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.blue.shade700),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Streaming...',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blue.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_coverLetter),
                    if (_coverLetter.isNotEmpty && !_isStreaming) ...[
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          ElevatedButton.icon(
                            onPressed: () {
                              // Copy to clipboard implementation
                            },
                            icon: const Icon(Icons.copy),
                            label: const Text('Copy'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            onPressed: _isSaving ? null : _saveCoverLetterAsPdf,
                            icon: _isSaving
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Icon(Icons.download),
                            label: const Text('Download PDF'),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _jobDescriptionController.dispose();
    super.dispose();
  }
}
