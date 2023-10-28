import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:marketplace/data/datasource/message/remote/booking_data_source.dart';
import 'package:marketplace/data/model/message/booking/data/booking_dto.dart';
import 'package:marketplace/data/model/message/booking/request/booking_reply_create_req_dto.dart';
import 'package:marketplace/data/model/message/booking/request/booking_review_create_req_dto.dart';
import 'package:marketplace/data/model/message/booking/data/booking_review_dto.dart';
import 'package:marketplace/data/model/message/booking/request/booking_create_req_dto.dart';
import 'package:marketplace/domain/entities/message/booking/booking_entity.dart';
import 'package:marketplace/domain/entities/message/booking/booking_review_entity.dart';
import 'package:marketplace/domain/repository/message/message_repository.dart';
import 'package:marketplace/domain/repository/message/booking_repository.dart';
import 'package:marketplace/utils/environments.dart';
import 'package:marketplace/utils/firebase_analytic.dart';

@dev
@prod
@demo
@Singleton(as: BookingRepository)
class BookingRepositoryImpl extends BookingRepository {
  final BookingDataSource _bookingDataSource;
  final MessageRepository _messageRepository;
  final FirebaseAnalytic _analytic;

  BookingRepositoryImpl(
    this._bookingDataSource,
    this._messageRepository,
    this._analytic,
  );

  @override
  Future<BookingEntity> assignSession({
    required String clientId,
    required DateTime dateTime,
    required String serviceId,
  }) async {
    final BookingDto assignSessionResponse =
        await _bookingDataSource.assignSession(
      BookingCreateReqDto(
        clientId: clientId,
        serviceId: serviceId,
        time: dateTime.toIso8601String(),
      ),
    );
    _messageRepository.sendAppointmentMessage(
      clientId,
      assignSessionResponse.id,
    );
    return assignSessionResponse.toModel();
  }

  @override
  Future<BookingEntity> fetchSession({required String sessionId}) async {
    final sessionData = await _bookingDataSource.fetchSession(sessionId);
    return sessionData.toModel();
  }

  @override
  Future<BookingReviewEntity> rateReview({
    required String reviewId,
    required String conversationId,
    required int rate,
    required String? text,
  }) async {
    final BookingReviewDto reviewData = await _bookingDataSource.postReview(
      reviewId,
      BookingReviewCreateReqDto(rate: rate, text: text),
    );
    _messageRepository.sendUpdateCustomMessage(conversationId, reviewId);
    _analytic.logRatingReview(
      rate: rate,
      hasText: text != null && text.trim().isNotEmpty,
    );
    return reviewData.toModel();
  }

  @override
  Future<BookingReviewEntity?> fetchReview({required String reviewId}) async {
    try {
      final BookingReviewDto newReviewData =
          await _bookingDataSource.fetchReview(reviewId);
      return newReviewData.toModel();
    } on DioError catch (e) {
      if (e.response?.statusCode == 400) {
        return null;
      }
      rethrow;
    }
  }

  @override
  Future<void> deleteReview({required String reviewId}) async {
    await _bookingDataSource.deleteReview(
      reviewId,
    );
    _analytic.logDeletingReview();
  }

  @override
  Future<BookingReviewEntity?> deleteReviewReply({
    required String reviewId,
  }) async {
    final BookingReviewDto reviewData =
        await _bookingDataSource.deleteReviewReply(
      reviewId,
    );
    _analytic.logDeleteAnswerToReview();
    return reviewData.toModel();
  }

  @override
  Future<BookingReviewEntity?> changeReview({
    required String reviewId,
    required String? text,
    required int rate,
  }) async {
    final BookingReviewDto reviewData = await _bookingDataSource.putReview(
      reviewId,
      BookingReviewCreateReqDto(rate: rate, text: text),
    );
    _analytic.logChangingReview(
      rate: rate,
      hasText: text != null && text.trim().isNotEmpty,
    );
    return reviewData.toModel();
  }

  @override
  Future<BookingReviewEntity?> changeReviewReply({
    required String reviewId,
    required String text,
  }) async {
    final BookingReviewDto reviewData = await _bookingDataSource.putReviewReply(
      reviewId,
      BookingReplyCreateReqDto(reply: text),
    );
    _analytic.logChangingAnswerToReview();
    return reviewData.toModel();
  }

  @override
  Future<BookingReviewEntity?> sendReviewReply({
    required String reviewId,
    required String text,
  }) async {
    final BookingReviewDto reviewData =
        await _bookingDataSource.postReviewReply(
      reviewId,
      BookingReplyCreateReqDto(reply: text),
    );
    _analytic.logAnswerToReview();
    return reviewData.toModel();
  }

  @override
  Future<List<BookingReviewEntity>?> fetchUserReviews({
    required String profileId,
  }) async {
    try {
      final List<BookingReviewDto> newReviewData =
          await _bookingDataSource.getUserReviews(profileId);
      return newReviewData.map((e) => e.toModel()).toList();
    } on DioError catch (e) {
      if (e.response?.statusCode == 400) {
        return null;
      }
      rethrow;
    }
  }
}
