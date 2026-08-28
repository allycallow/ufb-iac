# JSON Schema contracts for the `data` field of outbox_event rows (see
# upfrontbeats.services.kafka.OutboxEventService in the ufb repo). One schema
# per aggregate_type, since every event_type sharing an aggregate_type
# (created/updated) publishes an identical shape today.
#
# tracks/releases/artists/labels are backed by DRF ModelSerializers with
# `fields = "__all__"`, so their field set grows on every migration that adds
# a column. Locking those to an exact field list would hard-fail production on
# the next migration. They're intentionally left structural instead — only the
# `id` field (present on every BaseModel) is enforced, with
# additionalProperties left open. The other 8 aggregates are hand-built dicts
# with a fixed field set chosen by the developer, so those are enforced exactly.

resource "aws_glue_registry" "outbox_events" {
  registry_name = "${var.name}-outbox-events"
  description   = "JSON Schema contracts for ufb outbox_event payloads, one schema per aggregate_type"

  tags = var.tags
}

locals {
  uuid_string = { type = "string", format = "uuid" }

  id_ref_fields = {
    for name in [
      "user_id", "artist_id", "label_id", "collection_id", "track_id", "playlist_id",
    ] : name => local.uuid_string
  }

  named_ref = {
    type       = "object"
    properties = { id = local.uuid_string, name = { type = "string" } }
    required   = ["id", "name"]
  }

  schemas = {
    artist_follows = {
      type                 = "object"
      properties           = merge({ id = local.uuid_string }, { for k in ["user_id", "artist_id"] : k => local.id_ref_fields[k] })
      required             = ["id", "user_id", "artist_id"]
      additionalProperties = false
    }

    label_follows = {
      type                 = "object"
      properties           = merge({ id = local.uuid_string }, { for k in ["user_id", "label_id"] : k => local.id_ref_fields[k] })
      required             = ["id", "user_id", "label_id"]
      additionalProperties = false
    }

    collection_tracks = {
      type                 = "object"
      properties           = merge({ id = local.uuid_string }, { for k in ["collection_id", "track_id"] : k => local.id_ref_fields[k] })
      required             = ["id", "collection_id", "track_id"]
      additionalProperties = false
    }

    playlist_tracks = {
      type = "object"
      properties = merge(
        { id = local.uuid_string },
        { for k in ["playlist_id", "track_id"] : k => local.id_ref_fields[k] },
        { position = { type = "integer" } }
      )
      required             = ["id", "playlist_id", "track_id", "position"]
      additionalProperties = false
    }

    collections = {
      type = "object"
      properties = {
        id        = local.uuid_string
        track_ids = { type = "array", items = { type = "string", format = "uuid" } }
      }
      required             = ["id", "track_ids"]
      additionalProperties = false
    }

    users = {
      type = "object"
      properties = {
        id         = local.uuid_string
        first_name = { type = "string" }
        trial      = { type = "boolean" }
      }
      required             = ["id", "first_name", "trial"]
      additionalProperties = false
    }

    track_plays = {
      type = "object"
      properties = {
        id         = local.uuid_string
        track_id   = local.uuid_string
        play_date  = { type = "string", format = "date-time" }
        play_count = { type = "integer" }
      }
      required             = ["id", "track_id", "play_date", "play_count"]
      additionalProperties = false
    }

    playlists = {
      type = "object"
      properties = {
        id             = local.uuid_string
        name           = { type = "string" }
        sub_title      = { type = ["string", "null"] }
        description    = { type = ["string", "null"] }
        private        = { type = "boolean" }
        type           = { type = "string" }
        colour         = { type = ["string", "null"] }
        artwork_url    = { type = ["string", "null"] }
        hero_image_url = { type = ["string", "null"] }
        created_by_id  = { type = ["string", "null"], format = "uuid" }
        category       = { type = "array", items = local.named_ref }
        tags           = { type = "array", items = local.named_ref }
      }
      required = [
        "id", "name", "sub_title", "description", "private", "type", "colour",
        "artwork_url", "hero_image_url", "created_by_id", "category", "tags"
      ]
      additionalProperties = false
    }

    # Structural only — see file header comment.
    tracks = {
      type                 = "object"
      properties           = { id = local.uuid_string }
      required             = ["id"]
      additionalProperties = true
    }

    releases = {
      type                 = "object"
      properties           = { id = local.uuid_string }
      required             = ["id"]
      additionalProperties = true
    }

    artists = {
      type                 = "object"
      properties           = { id = local.uuid_string }
      required             = ["id"]
      additionalProperties = true
    }

    labels = {
      type                 = "object"
      properties           = { id = local.uuid_string }
      required             = ["id"]
      additionalProperties = true
    }
  }
}

resource "aws_glue_schema" "this" {
  for_each = local.schemas

  schema_name       = each.key
  registry_arn      = aws_glue_registry.outbox_events.arn
  data_format       = "JSON"
  compatibility     = "BACKWARD"
  schema_definition = jsonencode(each.value)

  tags = var.tags
}
