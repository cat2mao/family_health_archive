/// 人员类型
enum PersonType {
  human('human', '人'),
  cat('cat', '猫'),
  dog('dog', '狗'),
  otherPet('other_pet', '其他宠物');

  const PersonType(this.code, this.label);
  final String code;
  final String label;

  static PersonType fromCode(String code) =>
      PersonType.values.firstWhere((e) => e.code == code, orElse: () => PersonType.human);
}

/// 家庭关系
enum Relationship {
  self('self', '本人'),
  spouse('spouse', '配偶'),
  child('child', '子女'),
  parent('parent', '父母'),
  other('other', '其他');

  const Relationship(this.code, this.label);
  final String code;
  final String label;

  static Relationship fromCode(String code) =>
      Relationship.values.firstWhere((e) => e.code == code, orElse: () => Relationship.other);
}

/// 就诊类型
enum VisitType {
  outpatient('outpatient', '门诊'),
  emergency('emergency', '急诊'),
  inpatient('inpatient', '住院'),
  checkup('checkup', '体检'),
  vaccination('vaccination', '疫苗接种');

  const VisitType(this.code, this.label);
  final String code;
  final String label;

  static VisitType fromCode(String code) =>
      VisitType.values.firstWhere((e) => e.code == code, orElse: () => VisitType.outpatient);
}

/// 性别
enum Gender {
  male('male', '男'),
  female('female', '女'),
  unknown('unknown', '未知');

  const Gender(this.code, this.label);
  final String code;
  final String label;

  static Gender? fromCode(String? code) {
    if (code == null) return null;
    return Gender.values.firstWhere((e) => e.code == code, orElse: () => Gender.unknown);
  }
}

/// 附件类型
enum AttachmentType {
  medical('medical', '病例'),
  report('report', '检查报告'),
  prescription('prescription', '处方'),
  invoice('invoice', '发票'),
  other('other', '其他');

  const AttachmentType(this.code, this.label);
  final String code;
  final String label;

  static AttachmentType fromCode(String code) =>
      AttachmentType.values.firstWhere((e) => e.code == code, orElse: () => AttachmentType.other);
}

/// 附件文件类型
enum FileType {
  image('image', '图片'),
  pdf('pdf', 'PDF');

  const FileType(this.code, this.label);
  final String code;
  final String label;

  static FileType fromCode(String code) =>
      FileType.values.firstWhere((e) => e.code == code, orElse: () => FileType.image);
}

/// 标签类别
enum TagCategory {
  hospital('hospital', '医院'),
  condition('condition', '病情类别'),
  custom('custom', '自定义');

  const TagCategory(this.code, this.label);
  final String code;
  final String label;

  static TagCategory fromCode(String code) =>
      TagCategory.values.firstWhere((e) => e.code == code, orElse: () => TagCategory.custom);
}

/// 提醒类型
enum ReminderType {
  recheck('recheck', '复查'),
  medication('medication', '用药'),
  vaccination('vaccination', '疫苗'),
  deworming('deworming', '驱虫'),
  custom('custom', '自定义');

  const ReminderType(this.code, this.label);
  final String code;
  final String label;

  static ReminderType fromCode(String code) =>
      ReminderType.values.firstWhere((e) => e.code == code, orElse: () => ReminderType.custom);
}

/// 重复类型
enum RepeatType {
  once('once', '一次性'),
  daily('daily', '每天'),
  weekly('weekly', '每周'),
  monthly('monthly', '每月'),
  yearly('yearly', '每年');

  const RepeatType(this.code, this.label);
  final String code;
  final String label;

  static RepeatType fromCode(String code) =>
      RepeatType.values.firstWhere((e) => e.code == code, orElse: () => RepeatType.once);
}
