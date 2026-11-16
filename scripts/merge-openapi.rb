#!/usr/bin/env ruby
# frozen_string_literal: true

require 'yaml'
require 'fileutils'

FRAG_DIR = ENV.fetch('FRAG_DIR', File.expand_path('../openapi/fragments', __dir__))
OUT_FILE = File.expand_path('../openapi/openapi.yaml', __dir__)

DOMAINS = %w[inventory wardrobe pantry tasks notes subscriptions].freeze

# パラメータ名とスキーマ名の重複を解消するためのリネームマッピング
PARAM_RENAMES = {
  'NotesTimeField' => 'NotesTimeFieldQuery',
  'InventorySortOrder' => 'InventorySortOrderQuery'
}.freeze

def deep_transform_refs(node)
  case node
  when Hash
    if node['$ref']
      PARAM_RENAMES.each do |old_name, new_name|
        if node['$ref'] == "#/components/parameters/#{old_name}"
          node['$ref'] = "#/components/parameters/#{new_name}"
        end
      end
    end
    node.each { |_k, v| deep_transform_refs(v) }
  when Array
    node.each { |v| deep_transform_refs(v) }
  end
end

puts "Reading fragments from #{FRAG_DIR}..."

fragments = {}
DOMAINS.each do |domain|
  path = File.join(FRAG_DIR, "#{domain}.yaml")
  abort "Fragment not found: #{path}" unless File.exist?(path)
  fragments[domain] = YAML.load_file(path)
end

merged = {
  'openapi' => '3.0.3',
  'info' => {
    'title' => 'LifePipe API',
    'version' => '1.0.0',
    'description' => "Personal Life OS（LifePipe）の生活管理マイクロサービス群を束ねる edge（BFF）の外部 API 定義。\nブラウザ / TanStack Start フロントエンドと Go 製 edge サービス間の通信規約を定義する。\n6つの生活ドメイン（物品・衣服・食材在庫・タスク・メモ・固定費）の要件（docs/requirements/）に準拠。\n"
  },
  'servers' => [
    {
      'url' => '/api/v1',
      'description' => 'API v1'
    }
  ],
  'tags' => [
    { 'name' => 'inventory', 'description' => '物品・固定資産管理（Homebox 相当）' },
    { 'name' => 'wardrobe', 'description' => '衣服・ワードローブ管理（Wardrowbe 相当）' },
    { 'name' => 'pantry', 'description' => '食材・日用品在庫管理（Grocy 相当）' },
    { 'name' => 'tasks', 'description' => 'タスク・家事管理（Vikunja 相当）' },
    { 'name' => 'notes', 'description' => 'メモ・ログ管理（Memos 相当）' },
    { 'name' => 'subscriptions', 'description' => '固定費・サブスクリプション管理（Wallos 相当）' }
  ],
  'security' => [
    { 'bearerAuth' => [] }
  ],
  'paths' => {},
  'components' => {
    'securitySchemes' => {
      'bearerAuth' => {
        'type' => 'http',
        'scheme' => 'bearer',
        'bearerFormat' => 'JWT',
        'description' => 'OIDC ID 基盤（Zitadel 等）が発行した JWT アクセストークン'
      }
    },
    'parameters' => {
      'Page' => {
        'name' => 'page',
        'in' => 'query',
        'required' => false,
        'description' => '取得するページ番号（1始まり）',
        'schema' => {
          'type' => 'integer',
          'minimum' => 1,
          'default' => 1
        }
      },
      'PageSize' => {
        'name' => 'page_size',
        'in' => 'query',
        'required' => false,
        'description' => '1ページあたりの件数（既定50、最大200）',
        'schema' => {
          'type' => 'integer',
          'minimum' => 1,
          'maximum' => 200,
          'default' => 50
        }
      },
      'NotesPageSize' => {
        'name' => 'page_size',
        'in' => 'query',
        'required' => false,
        'description' => '1ページあたりの件数。メモ一覧の既定件数は 20、最大 100（NOT-BR-23）。',
        'schema' => {
          'type' => 'integer',
          'minimum' => 1,
          'maximum' => 100,
          'default' => 20
        }
      },
      'IdempotencyKey' => {
        'name' => 'Idempotency-Key',
        'in' => 'header',
        'required' => false,
        'description' => '操作の冪等性を担保するためのキー（UUID または一意な文字列）',
        'schema' => {
          'type' => 'string',
          'minLength' => 1,
          'maxLength' => 255
        }
      }
    },
    'responses' => {
      'BadRequest' => {
        'description' => 'リクエストが不正（パラメータ誤り、形式違反など）',
        'content' => {
          'application/problem+json' => {
            'schema' => { '$ref' => '#/components/schemas/Problem' }
          }
        }
      },
      'Unauthorized' => {
        'description' => '認証されていないか、認証トークンが無効または期限切れ',
        'content' => {
          'application/problem+json' => {
            'schema' => { '$ref' => '#/components/schemas/Problem' }
          }
        }
      },
      'NotFound' => {
        'description' => '要求されたリソースが存在しないか、権限がないため存在を隠蔽した',
        'content' => {
          'application/problem+json' => {
            'schema' => { '$ref' => '#/components/schemas/Problem' }
          }
        }
      },
      'Conflict' => {
        'description' => 'リソースの状態と競合した（一意性違反、配下リソースの存在など）',
        'content' => {
          'application/problem+json' => {
            'schema' => { '$ref' => '#/components/schemas/Problem' }
          }
        }
      },
      'UnprocessableEntity' => {
        'description' => '構文は正しいが、ドメイン業務ルールの制約に違反している',
        'content' => {
          'application/problem+json' => {
            'schema' => { '$ref' => '#/components/schemas/Problem' }
          }
        }
      }
    },
    'schemas' => {
      'Problem' => {
        'type' => 'object',
        'description' => 'RFC 9457 Problem Details for HTTP APIs',
        'required' => %w[type title status],
        'properties' => {
          'type' => {
            'type' => 'string',
            'format' => 'uri',
            'description' => 'エラーの種類を識別する URI',
            'example' => 'about:blank'
          },
          'title' => {
            'type' => 'string',
            'description' => 'エラーの簡潔な要約',
            'example' => 'Bad Request'
          },
          'status' => {
            'type' => 'integer',
            'description' => 'HTTP ステータスコード',
            'example' => 400
          },
          'detail' => {
            'type' => 'string',
            'description' => '人間が読めるエラーの詳細説明',
            'example' => 'Request validation failed'
          },
          'instance' => {
            'type' => 'string',
            'format' => 'uri-reference',
            'description' => 'エラーが発生した具体的なリソースの URI'
          },
          'invalid_params' => {
            'type' => 'array',
            'description' => 'バリデーションエラーの詳細',
            'items' => {
              'type' => 'object',
              'required' => %w[name reason],
              'properties' => {
                'name' => { 'type' => 'string', 'description' => 'エラーとなったフィールド名' },
                'reason' => { 'type' => 'string', 'description' => 'エラーの理由' }
              }
            }
          }
        }
      }
    }
  }
}

DOMAINS.each do |domain|
  doc = fragments[domain]
  deep_transform_refs(doc)

  # ドメインごとの個別調整
  if domain == 'notes'
    # NOT-BR-23: notes の一覧操作の PageSize を NotesPageSize に切り替え
    (doc['paths'] || {}).each do |_p, item|
      next unless item.is_a?(Hash)
      item.each do |_method, op|
        next unless op.is_a?(Hash) && op['parameters'].is_a?(Array)
        op['parameters'].each do |param|
          if param.is_a?(Hash) && param['$ref'] == '#/components/parameters/PageSize'
            param['$ref'] = '#/components/parameters/NotesPageSize'
          end
        end
      end
    end
  elsif domain == 'pantry'
    # pantryIngestPurchases に Idempotency-Key を追加
    purchases_path = doc.dig('paths', '/pantry/purchases', 'post')
    if purchases_path
      purchases_path['parameters'] ||= []
      unless purchases_path['parameters'].any? { |p| p['$ref'] == '#/components/parameters/IdempotencyKey' }
        purchases_path['parameters'] << { '$ref' => '#/components/parameters/IdempotencyKey' }
      end
    end
  elsif domain == 'subscriptions'
    # iCalendar 配信エンドポイントの認証緩和と token パラメータ
    ics_op = doc.dig('paths', '/subscriptions/subscriptions/upcoming.ics', 'get')
    if ics_op
      ics_op['security'] = [{ 'bearerAuth' => [] }, {}]
      ics_op['parameters'] ||= []
      unless ics_op['parameters'].any? { |p| p['name'] == 'token' }
        ics_op['parameters'] << {
          'name' => 'token',
          'in' => 'query',
          'required' => false,
          'description' => 'iCalendar 購読用トークン（bearerAuth ヘッダーを付与できない外部カレンダークライアント用）',
          'schema' => { 'type' => 'string' }
        }
      end
    end
  end

  # paths のマージ
  (doc['paths'] || {}).each do |p, item|
    if merged['paths'].key?(p)
      warn "WARNING: Duplicate path #{p} found in #{domain}"
    end
    merged['paths'][p] = item
  end

  # schemas のマージ
  (doc.dig('components', 'schemas') || {}).each do |k, v|
    if merged['components']['schemas'].key?(k)
      warn "WARNING: Duplicate schema #{k} found in #{domain}"
    end
    merged['components']['schemas'][k] = v
  end

  # parameters のマージ
  (doc.dig('components', 'parameters') || {}).each do |k, v|
    new_k = PARAM_RENAMES[k] || k
    if merged['components']['parameters'].key?(new_k)
      warn "WARNING: Duplicate parameter #{new_k} found in #{domain}"
    end
    merged['components']['parameters'][new_k] = v
  end

  # responses のマージ
  (doc.dig('components', 'responses') || {}).each do |k, v|
    if merged['components']['responses'].key?(k)
      warn "WARNING: Duplicate response #{k} found in #{domain}"
    end
    merged['components']['responses'][k] = v
  end
end

FileUtils.mkdir_p(File.dirname(OUT_FILE))
File.write(OUT_FILE, YAML.dump(merged))

puts "Successfully generated #{OUT_FILE}"
puts "Statistics:"
puts "  Paths:       #{merged['paths'].size}"
puts "  Schemas:     #{merged['components']['schemas'].size}"
puts "  Parameters:  #{merged['components']['parameters'].size}"
puts "  Responses:   #{merged['components']['responses'].size}"
