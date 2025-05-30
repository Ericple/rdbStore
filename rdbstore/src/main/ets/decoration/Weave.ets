/*
 * Copyright (2024) Bytedance Ltd. and/or its affiliates
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *    http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import { RdbConst } from '../RdbConst'
import { ConvertParameter } from '../model/relation/converter/ConvertParameter'
import { Constraint, Property } from '../model/relation/Property'
import { DbStructInfo } from '../model/relation/DbStructInfo'
import { TableMetaInfo } from '../model/relation/TableMetaInfo'
import { ColumnInfo } from './Column'
import { EmbeddedInfo } from './Embedded'
import { TableInfo } from './Entity'
import { ClassConstructor } from '../util/ClassConstructor'
import { IndexMetaInfo } from '../model/relation/IndexMetaInfo'
import { EmbeddedNode } from './EmbeddedNode'

export namespace Weave {

  /**
   * 解析装饰器生成表信息
   * @param entityCls
   */
  export function generateTableInfo(entityCls: ClassConstructor<Object>) {

    if (!DbStructInfo.getInstance().getTableMeta(entityCls)) {
      const tableInfo: TableInfo = entityCls[RdbConst.TABLE]
      generatePropertyInfo(tableInfo, entityCls)
    }

  }

  /**
   * 解析装饰器生成列信息
   * @param tableInfo
   * @param entityCls
   */
  function generatePropertyInfo(tableInfo: TableInfo, entityCls: ClassConstructor<Object>) {
    const tableMeta = new TableMetaInfo()
    tableMeta.tableName = tableInfo.tableName!
    tableMeta.entityCls = entityCls
    tableMeta.index =
      tableInfo.index?.map((item) => new IndexMetaInfo(item.name, item.columnName, item.unique)) ?? new Array
    DbStructInfo.getInstance().addTable(entityCls, tableMeta)

    const propArray: Array<Property> = new Array

    // 深度优先递归提取所有列信息
    depthTraversal(propArray, entityCls, '', '', tableMeta, [])

    // 关联表和列信息
    propArray.forEach(item => {
      DbStructInfo.getInstance().addProperty(entityCls, item)
    })
  }

  /**
   * 深度优先遍历，提取列信息
   * @param propArray
   * @param entityCls
   * @param propName
   * @param prefix
   * @param table
   * @param parentChain
   */
  function depthTraversal(propArray: Array<Property>, entityCls: ClassConstructor<Object>, propName: string,
    prefix: string, table: TableMetaInfo,
    parentChain: EmbeddedNode[]) {

    // 叶子结点解析生成 property
    if (isLeafNode(entityCls, propName)) {
      parseLeafNode(propArray, entityCls, propName, prefix, table, parentChain.slice())
      return
    }

    if (propName) {
      parentChain.push({
        propName: propName,
        cls: entityCls
      });
    }

    const entity = new entityCls();
    const props = Object.keys(entity);

    // 处理当前结点的所有子结点
    for (const child of props) {
      if (!ignoreNode(entityCls, child)) {
        const param: EmbeddedInfo<Object> =
          entityCls.prototype[RdbConst.EMBEDDED] ? entityCls.prototype[RdbConst.EMBEDDED][child] : undefined
        const prefix = param?.prefix ?? '';
        const targetClass = param?.targetClass ?? entityCls;
        depthTraversal(propArray, targetClass, child, prefix, table, parentChain);
      }
    }

    if (propName) {
      parentChain.pop()
    }
  }

  /**
   * 不带有列信息的节点
   */
  function ignoreNode(entityCls: ClassConstructor<Object>, propName: string) {
    if (propName) {
      const columnInfo: ColumnInfo =
        entityCls.prototype[RdbConst.COLUMN] ? entityCls.prototype[RdbConst.COLUMN][propName] : undefined
      const embedded: EmbeddedInfo<Object> =
        entityCls.prototype[RdbConst.EMBEDDED] ? entityCls.prototype[RdbConst.EMBEDDED][propName] : undefined
      if (!columnInfo && !embedded) {
        return true
      }
    }
    return false
  }


  /**
   * 是否叶子结点
   */
  function isLeafNode(entityCls: ClassConstructor<Object>, propName: string): boolean {
    if (entityCls.prototype[RdbConst.COLUMN] && entityCls.prototype[RdbConst.COLUMN][propName]) {
      return true
    }
    return false
  }

  /**
   * 解析叶子结点内容
   * @param propArray
   * @param entityCls
   * @param propName
   * @param prefix
   * @param table
   * @param embeddedChain
   */
  function parseLeafNode(propArray: Array<Property>, entityCls: ClassConstructor<Object>, propName: string,
    prefix: string, table: TableMetaInfo,
    embeddedChain: EmbeddedNode[]) {
    // 叶子节点列信息解析
    const columnInfo: ColumnInfo =
      entityCls.prototype[RdbConst.COLUMN] ? entityCls.prototype[RdbConst.COLUMN][propName] : undefined

    if (columnInfo) {

      if (prefix) {
        columnInfo.name = columnInfo.name + prefix
      }

      const prop =
        new Property(table.tableName, columnInfo.type, propName, columnInfo.isPrimaryKey ?? false, columnInfo.name!,
          columnInfo.autoincrement ?? false, embeddedChain,
          columnInfo.convertor ? new ConvertParameter(columnInfo.convertor, columnInfo.type) : undefined,
          new Constraint(columnInfo.unique ?? false, columnInfo.notNull ?? false));
      propArray.push(prop)
    }
  }
}