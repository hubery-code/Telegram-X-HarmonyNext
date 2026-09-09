import { describe, it, expect } from '@ohos/hypium';
import { RdbKvStatements } from '../main/ets/core/RdbKvStatements';
import { PreferenceWrite } from '../main/ets/core/PreferenceStoreCore';

export default function rdbKvStatementsTest() {
  describe('RdbKvStatements', () => {
    it('createKvTable_coversAllColumns', 0, () => {
      const s = RdbKvStatements.createKvTable();
      expect(s.sql.indexOf('CREATE TABLE IF NOT EXISTS tgx_kv') >= 0).assertTrue();
      expect(s.sql.indexOf('key TEXT PRIMARY KEY NOT NULL') >= 0).assertTrue();
      expect(s.sql.indexOf('type_tag INTEGER NOT NULL') >= 0).assertTrue();
      expect(s.sql.indexOf('value_text TEXT') >= 0).assertTrue();
      expect(s.sql.indexOf('value_real REAL') >= 0).assertTrue();
      expect(s.sql.indexOf('value_integer INTEGER') >= 0).assertTrue();
      expect(s.args.length).assertEqual(0);
    });

    it('createMetaTable_coversVersionMarker', 0, () => {
      const s = RdbKvStatements.createMetaTable();
      expect(s.sql.indexOf('CREATE TABLE IF NOT EXISTS tgx_meta') >= 0).assertTrue();
      expect(s.sql.indexOf('value INTEGER NOT NULL') >= 0).assertTrue();
    });

    it('upsertKv_bindsArgsInColumnOrder', 0, () => {
      const s = RdbKvStatements.upsertKv('k1', 'v1');
      expect(s.sql.indexOf('INSERT OR REPLACE INTO tgx_kv') >= 0).assertTrue();
      expect(s.args.length).assertEqual(5);
      expect(s.args[0]).assertEqual('k1');
      expect(s.args[1]).assertEqual(0);
      expect(s.args[2]).assertEqual('v1');
      expect(s.args[3] === null).assertTrue();
      expect(s.args[4] === null).assertTrue();
    });

    it('deleteKv_bindsKey', 0, () => {
      const s = RdbKvStatements.deleteKv('k1');
      expect(s.sql.indexOf('DELETE FROM tgx_kv WHERE key = ?') >= 0).assertTrue();
      expect(s.args.length).assertEqual(1);
      expect(s.args[0]).assertEqual('k1');
    });

    it('selectAllKv_selectsAllValueColumns', 0, () => {
      const s = RdbKvStatements.selectAllKv();
      expect(s.sql.indexOf('SELECT key, type_tag, value_text, value_real, value_integer FROM tgx_kv') >= 0).assertTrue();
    });

    it('userVersionStatements_bindKeyAndVersion', 0, () => {
      const sel = RdbKvStatements.selectUserVersion();
      expect(sel.sql.indexOf('SELECT value FROM tgx_meta WHERE key = ?') >= 0).assertTrue();
      expect(sel.args[0]).assertEqual('user_version');
      const upsert = RdbKvStatements.upsertUserVersion(3);
      expect(upsert.sql.indexOf('INSERT OR REPLACE INTO tgx_meta') >= 0).assertTrue();
      expect(upsert.args[0]).assertEqual('user_version');
      expect(upsert.args[1]).assertEqual(3);
    });

    it('buildWrites_mapsPutsAndDeletesInOrder', 0, () => {
      const writes: PreferenceWrite[] = [
        { kind: 'put', key: 'a', value: 1 },
        { kind: 'delete', key: 'b' },
        { kind: 'put', key: 'c', value: true }
      ];
      const statements = RdbKvStatements.buildWrites(writes);
      expect(statements.length).assertEqual(3);
      expect(statements[0].sql.indexOf('INSERT OR REPLACE') >= 0).assertTrue();
      expect(statements[0].args[0]).assertEqual('a');
      expect(statements[1].sql.indexOf('DELETE') >= 0).assertTrue();
      expect(statements[2].args[1]).assertEqual(2);
    });
  });
}
