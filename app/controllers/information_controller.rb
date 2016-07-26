class InformationController < ApplicationController
  def show
    lists = [
      '2016/07/27 トップページのレイアウトを修正しました',
      '2016/07/26 トップページのレイアウトを修正しました',
      '2016/07/25 ページの読み込みを高速化しました',
      '2016/07/24 スマートフォン向けのアイコンを設置しました',
    ]
    render json: {status: 200, html: lists.join('<br>')}, status: 200
  end
end
