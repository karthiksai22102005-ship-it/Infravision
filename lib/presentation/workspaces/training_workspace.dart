import 'package:flutter/material.dart';
import '../../config/app_theme.dart';
import '../../vision/training/dataset_manager.dart';
import '../../vision/training/training_pipeline_engine.dart';

/// Real-Time Neural Network Training Pipeline Console.
class TrainingWorkspace extends StatefulWidget {
  const TrainingWorkspace({super.key});

  @override
  State<TrainingWorkspace> createState() => _TrainingWorkspaceState();
}

class _TrainingWorkspaceState extends State<TrainingWorkspace> {
  final TrainingPipelineEngine _trainer = TrainingPipelineEngine.instance;
  final DatasetManager _dataset = DatasetManager.instance;
  final ScrollController _logScrollController = ScrollController();

  @override
  void dispose() {
    _logScrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_logScrollController.hasClients) {
      _logScrollController.animateTo(
        _logScrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = AppTheme.isMobile(context);

    return ListenableBuilder(
      listenable: Listenable.merge([_trainer, _dataset]),
      builder: (context, _) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

        return SingleChildScrollView(
          padding: EdgeInsets.all(isMobile ? 16 : 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Header with Status
              _buildHeader(context),
              const SizedBox(height: 20),

              // 2. Training Controls & Real-Time Telemetry Layout
              if (!isMobile)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Left Column: Architecture & Hyperparameter Configuration
                    Expanded(
                      flex: 5,
                      child: _buildConfigPanel(context),
                    ),
                    const SizedBox(width: 20),
                    // Right Column: Real-Time Loss/Accuracy Curves & Live Logs
                    Expanded(
                      flex: 7,
                      child: Column(
                        children: [
                          _buildLiveChartsCard(context),
                          const SizedBox(height: 20),
                          _buildLogConsoleCard(context),
                        ],
                      ),
                    ),
                  ],
                )
              else ...[
                _buildConfigPanel(context),
                const SizedBox(height: 20),
                _buildLiveChartsCard(context),
                const SizedBox(height: 20),
                _buildLogConsoleCard(context),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.bgSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
        boxShadow: AppTheme.shadowSm,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.primaryLight,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.model_training_rounded, color: AppTheme.primary, size: 24),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Real-Time Model Training & Fine-Tuning Console',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Fine-tune edge neural classifiers with on-device transfer learning and live epoch telemetry.',
                  style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          if (_trainer.isTraining)
            FilledButton.icon(
              onPressed: _trainer.stopTraining,
              icon: const Icon(Icons.stop_rounded, size: 18),
              label: const Text('Abort Training'),
              style: FilledButton.styleFrom(backgroundColor: AppTheme.error),
            )
          else
            FilledButton.icon(
              onPressed: _trainer.startTraining,
              icon: const Icon(Icons.play_arrow_rounded, size: 18),
              label: const Text('Start Real-Time Training'),
            ),
        ],
      ),
    );
  }

  Widget _buildConfigPanel(BuildContext context) {
    final disabled = _trainer.isTraining;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.bgSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
        boxShadow: AppTheme.shadowSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.tune_rounded, color: AppTheme.primary, size: 18),
              SizedBox(width: 8),
              Text(
                'Training Hyperparameters',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 1. Model Architecture
          const Text('Neural Backbone Architecture', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
          const SizedBox(height: 6),
          DropdownButtonFormField<ModelArchitecture>(
            initialValue: _trainer.architecture,
            decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
            items: ModelArchitecture.values.map((arch) {
              return DropdownMenuItem(
                value: arch,
                child: Text(arch.displayName, style: const TextStyle(fontSize: 12)),
              );
            }).toList(),
            onChanged: disabled ? null : (v) => v != null ? _trainer.setArchitecture(v) : null,
          ),
          const SizedBox(height: 16),

          // 2. Epochs
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Training Epochs', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
              Text('${_trainer.epochs} Epochs', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.primary)),
            ],
          ),
          Slider(
            value: _trainer.epochs.toDouble(),
            min: 5,
            max: 50,
            divisions: 9,
            activeColor: AppTheme.primary,
            onChanged: disabled ? null : (v) => _trainer.setEpochs(v.toInt()),
          ),
          const SizedBox(height: 10),

          // 3. Batch Size
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Batch Size', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
              Text('${_trainer.batchSize} samples / batch', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.primary)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [8, 16, 32, 64].map((bs) {
              final isPicked = _trainer.batchSize == bs;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: OutlinedButton(
                    onPressed: disabled ? null : () => _trainer.setBatchSize(bs),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: isPicked ? AppTheme.primaryLight : Colors.transparent,
                      side: BorderSide(color: isPicked ? AppTheme.primary : AppTheme.border),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    child: Text(
                      '$bs',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isPicked ? FontWeight.w700 : FontWeight.w500,
                        color: isPicked ? AppTheme.primary : AppTheme.textPrimary,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

          // 4. Learning Rate & Optimizer
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Learning Rate', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<double>(
                      initialValue: _trainer.learningRate,
                      decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                      items: const [
                        DropdownMenuItem(value: 0.01, child: Text('0.01 (Aggressive)', style: TextStyle(fontSize: 12))),
                        DropdownMenuItem(value: 0.001, child: Text('0.001 (Recommended)', style: TextStyle(fontSize: 12))),
                        DropdownMenuItem(value: 0.0001, child: Text('0.0001 (Fine-tuning)', style: TextStyle(fontSize: 12))),
                      ],
                      onChanged: disabled ? null : (v) => v != null ? _trainer.setLearningRate(v) : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Optimizer', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      initialValue: _trainer.optimizer,
                      decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                      items: const [
                        DropdownMenuItem(value: 'AdamW', child: Text('AdamW (Weight Decay)', style: TextStyle(fontSize: 12))),
                        DropdownMenuItem(value: 'Adam', child: Text('Adam', style: TextStyle(fontSize: 12))),
                        DropdownMenuItem(value: 'SGD', child: Text('SGD + Momentum', style: TextStyle(fontSize: 12))),
                      ],
                      onChanged: disabled ? null : (v) => v != null ? _trainer.setOptimizer(v) : null,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Dataset Readiness
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.bgSurfaceSubtle,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: AppTheme.success, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Dataset Ready (${_dataset.totalSamples} samples)',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '80% Train (${(_dataset.totalSamples * 0.8).round()}) • 20% Validation (${(_dataset.totalSamples * 0.2).round()})',
                        style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Export Model Section
          if (_trainer.isCompleted) ...[
            const Divider(color: AppTheme.border),
            const SizedBox(height: 12),
            const Row(
              children: [
                Icon(Icons.file_download_done_rounded, color: AppTheme.success, size: 18),
                SizedBox(width: 8),
                Text(
                  'Model Artifacts Export',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () => _exportModel('TFLite'),
                  icon: const Icon(Icons.android_rounded, size: 16),
                  label: const Text('Export .tflite (APK ready)', style: TextStyle(fontSize: 12)),
                ),
                OutlinedButton.icon(
                  onPressed: () => _exportModel('ONNX'),
                  icon: const Icon(Icons.hub_rounded, size: 16),
                  label: const Text('Export .onnx', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLiveChartsCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.bgSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
        boxShadow: AppTheme.shadowSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.show_chart_rounded, color: AppTheme.primary, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Live Convergence & Accuracy Curves',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                  ),
                ],
              ),
              if (_trainer.isTraining)
                Text(
                  'Epoch ${_trainer.currentEpoch}/${_trainer.epochs}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.primary),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // Custom Animated Canvas Chart
          SizedBox(
            height: 180,
            width: double.infinity,
            child: _trainer.epochHistory.isEmpty
                ? Center(
                    child: Text(
                      _trainer.isTraining
                          ? 'Initializing epoch gradients...'
                          : 'Press "Start Real-Time Training" to begin pipeline execution.',
                      style: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
                    ),
                  )
                : CustomPaint(
                    painter: _TrainingChartPainter(
                      history: _trainer.epochHistory,
                      totalEpochs: _trainer.epochs,
                    ),
                  ),
          ),
          const SizedBox(height: 12),

          // Legend
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildChartLegend(color: AppTheme.primary, label: 'Train Accuracy'),
              const SizedBox(width: 16),
              _buildChartLegend(color: AppTheme.success, label: 'Val Accuracy'),
              const SizedBox(width: 16),
              _buildChartLegend(color: AppTheme.error, label: 'Train Loss'),
              const SizedBox(width: 16),
              _buildChartLegend(color: AppTheme.warning, label: 'Val Loss'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChartLegend({required Color color, required String label}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 12, height: 4, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary, fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildLogConsoleCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A), // Dark slate terminal
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1E293B)),
        boxShadow: AppTheme.shadowSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(width: 8, height: 8, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF10B981))),
                  const SizedBox(width: 8),
                  const Text(
                    'Training Console Stream',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFE2E8F0)),
                  ),
                ],
              ),
              IconButton(
                onPressed: _trainer.clearLogs,
                icon: const Icon(Icons.clear_all_rounded, color: Colors.white54, size: 16),
                tooltip: 'Clear Console',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            height: 140,
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFF090D16),
              borderRadius: BorderRadius.circular(8),
            ),
            child: _trainer.logs.isEmpty
                ? const Center(
                    child: Text(
                      'Ready. Console logs will appear during training.',
                      style: TextStyle(color: Colors.white38, fontSize: 11, fontFamily: 'monospace'),
                    ),
                  )
                : ListView.builder(
                    controller: _logScrollController,
                    padding: const EdgeInsets.all(10),
                    itemCount: _trainer.logs.length,
                    itemBuilder: (context, idx) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          _trainer.logs[idx],
                          style: const TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 11,
                            fontFamily: 'monospace',
                            height: 1.4,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _exportModel(String format) async {
    final path = await _trainer.exportModelWeights(format: format);
    if (mounted && path != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Successfully exported $format model to $path'),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

/// Custom painter for rendering live training curves without external chart library deps.
class _TrainingChartPainter extends CustomPainter {
  _TrainingChartPainter({
    required this.history,
    required this.totalEpochs,
  });

  final List<EpochMetric> history;
  final int totalEpochs;

  @override
  void paint(Canvas canvas, Size size) {
    if (history.isEmpty) return;

    final gridPaint = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..strokeWidth = 1;

    // Draw horizontal grid lines
    for (int i = 0; i <= 4; i++) {
      final y = size.height * (i / 4.0);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final trainAccPaint = Paint()
      ..color = AppTheme.primary
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    final valAccPaint = Paint()
      ..color = AppTheme.success
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    final trainLossPaint = Paint()
      ..color = AppTheme.error
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final valLossPaint = Paint()
      ..color = AppTheme.warning
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final trainAccPath = Path();
    final valAccPath = Path();
    final trainLossPath = Path();
    final valLossPath = Path();

    for (int i = 0; i < history.length; i++) {
      final m = history[i];
      final x = (i / (totalEpochs > 1 ? totalEpochs - 1 : 1)) * size.width;

      // Accuracy 0.0 to 1.0 -> Height (inverted)
      final yTrainAcc = (1.0 - m.trainAccuracy) * size.height;
      final yValAcc = (1.0 - m.valAccuracy) * size.height;

      // Loss 0.0 to 2.5 -> Height (inverted)
      final yTrainLoss = (1.0 - (m.trainLoss / 2.5).clamp(0.0, 1.0)) * size.height;
      final yValLoss = (1.0 - (m.valLoss / 2.5).clamp(0.0, 1.0)) * size.height;

      if (i == 0) {
        trainAccPath.moveTo(x, yTrainAcc);
        valAccPath.moveTo(x, yValAcc);
        trainLossPath.moveTo(x, yTrainLoss);
        valLossPath.moveTo(x, yValLoss);
      } else {
        trainAccPath.lineTo(x, yTrainAcc);
        valAccPath.lineTo(x, yValAcc);
        trainLossPath.lineTo(x, yTrainLoss);
        valLossPath.lineTo(x, yValLoss);
      }
    }

    canvas.drawPath(trainLossPath, trainLossPaint);
    canvas.drawPath(valLossPath, valLossPaint);
    canvas.drawPath(trainAccPath, trainAccPaint);
    canvas.drawPath(valAccPath, valAccPaint);
  }

  @override
  bool shouldRepaint(covariant _TrainingChartPainter oldDelegate) => true;
}
