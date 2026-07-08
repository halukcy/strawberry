/*
 * Strawberry Music Player
 * Copyright 2026
 *
 * Strawberry is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * Strawberry is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with Strawberry.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

#include "config.h"

#include <QtGlobal>
#if defined(Q_OS_MACOS)

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <MediaPlayer/MediaPlayer.h>

#include <QDir>
#include <QFile>
#include <QMetaObject>

#include "core/logging.h"
#include "core/player.h"
#include "core/song.h"
#include "covermanager/albumcoverloaderresult.h"

#include "macnowplaying.h"

namespace {

static NSMutableDictionary *EnsureNowPlayingInfo() {
  NSDictionary *existing = [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo;
  if (existing) {
    return [[existing mutableCopy] autorelease];
  }
  return [NSMutableDictionary dictionary];
}

static void SetNowPlayingInfo(NSDictionary *info) {
  [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = info;
}

}  // namespace

MacNowPlaying::MacNowPlaying(SharedPtr<Player> player, QObject *parent)
    : QObject(parent),
      player_(player),
      state_(EngineBase::State::Empty),
      play_target_(nullptr),
      pause_target_(nullptr),
      toggle_target_(nullptr),
      stop_target_(nullptr),
      next_target_(nullptr),
      previous_target_(nullptr) {}

MacNowPlaying::~MacNowPlaying() {

  MPRemoteCommandCenter *cc = [MPRemoteCommandCenter sharedCommandCenter];

  if (play_target_) [cc.playCommand removeTarget:(id)play_target_];
  if (pause_target_) [cc.pauseCommand removeTarget:(id)pause_target_];
  if (toggle_target_) [cc.togglePlayPauseCommand removeTarget:(id)toggle_target_];
  if (stop_target_) [cc.stopCommand removeTarget:(id)stop_target_];
  if (next_target_) [cc.nextTrackCommand removeTarget:(id)next_target_];
  if (previous_target_) [cc.previousTrackCommand removeTarget:(id)previous_target_];

  SetNowPlayingInfo(nil);

  if (!temp_art_path_.isEmpty()) {
    QFile::remove(temp_art_path_);
  }

}

bool MacNowPlaying::Initialize() {

  MPRemoteCommandCenter *cc = [MPRemoteCommandCenter sharedCommandCenter];

  cc.playCommand.enabled = YES;
  cc.pauseCommand.enabled = YES;
  cc.togglePlayPauseCommand.enabled = YES;
  cc.stopCommand.enabled = YES;
  cc.nextTrackCommand.enabled = YES;
  cc.previousTrackCommand.enabled = YES;

  // Use blocks and jump back into the Qt thread.
  play_target_ = [cc.playCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *) {
    QMetaObject::invokeMethod(&*player_, "Play", Qt::QueuedConnection);
    return MPRemoteCommandHandlerStatusSuccess;
  }];

  pause_target_ = [cc.pauseCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *) {
    QMetaObject::invokeMethod(&*player_, "Pause", Qt::QueuedConnection);
    return MPRemoteCommandHandlerStatusSuccess;
  }];

  toggle_target_ = [cc.togglePlayPauseCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *) {
    QMetaObject::invokeMethod(&*player_, "PlayPauseHelper", Qt::QueuedConnection);
    return MPRemoteCommandHandlerStatusSuccess;
  }];

  stop_target_ = [cc.stopCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *) {
    QMetaObject::invokeMethod(&*player_, "Stop", Qt::QueuedConnection);
    return MPRemoteCommandHandlerStatusSuccess;
  }];

  next_target_ = [cc.nextTrackCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *) {
    QMetaObject::invokeMethod(&*player_, "Next", Qt::QueuedConnection);
    return MPRemoteCommandHandlerStatusSuccess;
  }];

  previous_target_ = [cc.previousTrackCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *) {
    QMetaObject::invokeMethod(&*player_, "Previous", Qt::QueuedConnection);
    return MPRemoteCommandHandlerStatusSuccess;
  }];

  qLog(Info) << "MacNowPlaying: Initialized";
  return true;

}

void MacNowPlaying::EngineStateChanged(const EngineBase::State state) {
  state_ = state;
  UpdatePlaybackStatus(state);
}

void MacNowPlaying::CurrentSongChanged(const Song &song) {
  current_song_url_ = song.url();
  UpdateMetadata(song);
}

void MacNowPlaying::AlbumCoverLoaded(const Song &song, const AlbumCoverLoaderResult &result) {

  if (song.url() != current_song_url_) return;

  if (!result.success || result.album_cover.image.isNull()) {
    ClearArtwork();
    return;
  }

  if (temp_art_path_.isEmpty()) {
    temp_art_path_ = QDir::tempPath() + QStringLiteral("/strawberry_nowplaying_art.jpg");
  }

  if (!result.album_cover.image.save(temp_art_path_, "JPEG", 90)) {
    ClearArtwork();
    return;
  }

  NSImage *img = [[[NSImage alloc] initWithContentsOfFile:temp_art_path_.toNSString()] autorelease];
  if (!img) {
    ClearArtwork();
    return;
  }

  NSMutableDictionary *info = EnsureNowPlayingInfo();

  // MPMediaItemArtwork is available on macOS and is what Control Center expects.
  MPMediaItemArtwork *artwork = [[[MPMediaItemArtwork alloc] initWithBoundsSize:img.size
                                                                requestHandler:^NSImage *(NSSize) {
                                                                  return img;
                                                                }] autorelease];
  if (artwork) {
    [info setObject:artwork forKey:MPMediaItemPropertyArtwork];
    SetNowPlayingInfo(info);
  }

}

void MacNowPlaying::ClearArtwork() {
  NSMutableDictionary *info = EnsureNowPlayingInfo();
  [info removeObjectForKey:MPMediaItemPropertyArtwork];
  SetNowPlayingInfo(info);
}

void MacNowPlaying::UpdatePlaybackStatus(const EngineBase::State state) {

  NSMutableDictionary *info = EnsureNowPlayingInfo();

  // PlaybackRate is what most clients use to show play/pause state.
  double rate = 0.0;
  switch (state) {
    case EngineBase::State::Playing:
      rate = 1.0;
      break;
    case EngineBase::State::Paused:
    case EngineBase::State::Idle:
    case EngineBase::State::Empty:
    case EngineBase::State::Error:
      rate = 0.0;
      break;
  }

  [info setObject:[NSNumber numberWithDouble:rate] forKey:MPNowPlayingInfoPropertyPlaybackRate];
  SetNowPlayingInfo(info);

}

void MacNowPlaying::UpdateMetadata(const Song &song) {

  if (!song.is_valid()) {
    SetNowPlayingInfo(nil);
    return;
  }

  NSMutableDictionary *info = EnsureNowPlayingInfo();

  [info setObject:song.title().toNSString() forKey:MPMediaItemPropertyTitle];

  const QString artist = song.effective_albumartist().isEmpty() ? song.artist() : song.effective_albumartist();
  if (!artist.isEmpty()) {
    [info setObject:artist.toNSString() forKey:MPMediaItemPropertyArtist];
  }

  if (!song.album().isEmpty()) {
    [info setObject:song.album().toNSString() forKey:MPMediaItemPropertyAlbumTitle];
  }

  const double duration_s = song.length_nanosec() > 0 ? static_cast<double>(song.length_nanosec()) / 1000000000.0 : 0.0;
  if (duration_s > 0.0) {
    [info setObject:[NSNumber numberWithDouble:duration_s] forKey:MPMediaItemPropertyPlaybackDuration];
  }

  // Ensure playback rate is consistent with the latest state.
  [info setObject:[NSNumber numberWithDouble:(state_ == EngineBase::State::Playing ? 1.0 : 0.0)] forKey:MPNowPlayingInfoPropertyPlaybackRate];

  SetNowPlayingInfo(info);

}

#endif  // Q_OS_MACOS

