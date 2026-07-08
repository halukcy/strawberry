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

#ifndef MACNOWPLAYING_H
#define MACNOWPLAYING_H

#include "config.h"

#include <QObject>
#include <QUrl>

#include "includes/shared_ptr.h"
#include "engine/enginebase.h"

class Player;
class Song;
class AlbumCoverLoaderResult;

class MacNowPlaying : public QObject {
  Q_OBJECT

 public:
  explicit MacNowPlaying(SharedPtr<Player> player, QObject *parent = nullptr);
  ~MacNowPlaying() override;

  bool Initialize();

 public Q_SLOTS:
  void EngineStateChanged(EngineBase::State state);
  void CurrentSongChanged(const Song &song);
  void AlbumCoverLoaded(const Song &song, const AlbumCoverLoaderResult &result);

 private:
  void UpdatePlaybackStatus(EngineBase::State state);
  void UpdateMetadata(const Song &song);
  void ClearArtwork();

  SharedPtr<Player> player_;
  EngineBase::State state_;
  QUrl current_song_url_;
  QString temp_art_path_;

  void *play_target_;      // id (MPRemoteCommand target)
  void *pause_target_;     // id
  void *toggle_target_;    // id
  void *stop_target_;      // id
  void *next_target_;      // id
  void *previous_target_;  // id
};

#endif  // MACNOWPLAYING_H

