import 'package:flutter_test/flutter_test.dart';

import 'package:flutterjm/core/crypto_utils.dart';
import 'package:flutterjm/data/models.dart';

void main() {
  test('线路清单密文可解出合法 JSON', () {
    // 实测抓取的 newsvr-2025.txt（已清洗 BOM / 换行）。
    const cipher =
        'X+bnzYIcwF6C7Rd3T7njPErjfPO12gw6b1UQbMx53J7eJnjoOOhKBOjz085QJ2PESutvUIqk'
        'J3UVzPW4o7WbmCbSsN2AQANumvn8tOnTbM0EvvHfFaiMo0ZgXsDGe4QytJpsAZ/omt9p+Y3WY'
        'qhOaisTXyTFXssTmMNp8z3yev8e0QoVtBqmUkRYtLyA832v2d7CuZG7HLrTe+OvzffAv7nFKcVD'
        'I7DrYtWYkDmDjwqoQHC/J1GdLVJwYVKy/FziVxIaFIFH+vYnNiYGUvchY76W66qzAfsVACsCet0'
        '90hffW0gIhWCInxJUINJ817E7AH5RMl9WhEMvsyrY8yvDpdH3Wjck7NX42iUamIvTCJJBmLYqMz'
        'bF5WOfXM0l6+xFf7JY8aLzf8LAWhgjoDJxP2khYYg8X33dL4AKqG3kEWQ=';

    final plain = aesEcbDecryptBase64(
      cipher,
      md5Hex('diosfjckwpqpdfjkvnqQjsik'),
    );

    expect(plain, contains('"Server"'));
    expect(plain, contains('www.cdnbtd.cc'));
  });

  test('封面地址按 media/albums/{id}.jpg 兜底', () {
    const album = AlbumSummary(
      id: '1490490',
      name: 'x',
      author: '',
      description: '',
      image: '',
      categoryTitle: '',
      categorySubTitle: '',
      updateAt: 0,
      addDate: '',
    );
    expect(
      album.coverUrl('https://cdn-msp.jmdanjonproxy.vip'),
      'https://cdn-msp.jmdanjonproxy.vip/media/albums/1490490.jpg',
    );
  });
}
