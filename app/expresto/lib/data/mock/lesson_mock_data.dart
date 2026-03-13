import 'package:expresto/models/lesson_data.dart';
import 'package:flutter/material.dart';

final LessonData lessonMockDataHELP = LessonData(
  title: 'Emergency Signs -\nLesson 3',
  signWord: 'HELP',
  currentStep: 3,
  totalSteps: 20,
  progress: 0.15,
  emojiDemonstration: Icons.waving_hand,
  keyPoints: [
    'Raise both hands to shoulder height',
    'Palms facing forward',
    'Slight shaking motion',
    'Urgent facial expression',
  ],
  feedback: [
    const LessonFeedback(icon: Icons.check_circle, text: 'Good hand position!'),
    const LessonFeedback(
      icon: Icons.warning_amber_rounded,
      text: 'Raise hands a bit higher',
    ),
    const LessonFeedback(
      icon: Icons.task_alt,
      text: 'Facial expression: Perfect!',
    ),
  ],
  confidenceScore: 87,
  attemptNumber: 2,
  totalAttempts: 3,
);

final LessonData lessonMockDataWATER = LessonData(
  title: 'Emergency Signs -\nLesson 4',
  signWord: 'WATER',
  currentStep: 4,
  totalSteps: 20,
  progress: 0.20,
  emojiDemonstration: Icons.water_drop_outlined,
  keyPoints: [
    'Form a "W" with your index, middle, and ring fingers',
    'Tap the index finger against your chin twice',
    'Keep your other fingers curled',
    'Maintain eye contact',
  ],
  feedback: [
    const LessonFeedback(icon: Icons.check_circle, text: 'Good "W" shape!'),
    const LessonFeedback(
      icon: Icons.task_alt,
      text: 'Contact point is correct!',
    ),
  ],
  confidenceScore: 92,
  attemptNumber: 1,
  totalAttempts: 3,
);

final LessonData lessonMockDataAMBULANCE = LessonData(
  title: 'Medical Signs -\nLesson 1',
  signWord: 'AMBULANCE',
  currentStep: 1,
  totalSteps: 25,
  progress: 0.04,
  emojiDemonstration: Icons.emergency,
  keyPoints: [
    'Raise one hand above your head',
    'Rotate wrist like a siren',
    'Urgent facial expression',
  ],
  feedback: [
    const LessonFeedback(
      icon: Icons.warning_amber_rounded,
      text: 'Make the rotation more circular',
    ),
    const LessonFeedback(icon: Icons.task_alt, text: 'Good height!'),
  ],
  confidenceScore: 78,
  attemptNumber: 2,
  totalAttempts: 3,
);

final LessonData lessonMockDataFIRE = LessonData(
  title: 'Fire & Safety -\nLesson 2',
  signWord: 'FIRE',
  currentStep: 2,
  totalSteps: 15,
  progress: 0.13,
  emojiDemonstration: Icons.local_fire_department,
  keyPoints: [
    'Wiggle fingers pointing upwards',
    'Move hands up and down alternating',
    'Express urgency',
  ],
  feedback: [
    const LessonFeedback(
      icon: Icons.check_circle,
      text: 'Good finger wiggling!',
    ),
    const LessonFeedback(
      icon: Icons.task_alt,
      text: 'Great alternating motion!',
    ),
    const LessonFeedback(
      icon: Icons.warning_amber_rounded,
      text: 'Show more urgency in face',
    ),
  ],
  confidenceScore: 85,
  attemptNumber: 1,
  totalAttempts: 3,
);
